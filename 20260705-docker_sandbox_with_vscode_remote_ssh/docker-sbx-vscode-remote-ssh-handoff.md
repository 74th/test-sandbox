# Docker Sandbox + VS Code Remote SSH 作業引き継ぎメモ

作成日: 2026-07-05  
対象: Docker `sbx` sandbox 上に SSH server を立て、VS Code Remote SSH で接続する構成

## 目的

Docker の `sbx` / Docker Sandbox を使って sandbox 環境を作成し、VS Code の Remote SSH で sandbox 内の workspace を開けるようにする。

最終的には、以下に近い操作をスクリプト化したい。

```bash
sbx run -d shell --name v1-sandbox --kit ./sbx-sshd-v1 .
sbx ports v1-sandbox --publish 127.0.0.1:2222:2222/tcp4
code --remote ssh-remote+sbx-v1 "$(pwd)"
```

## 現在の結論

`sbx run shell --name v1-sandbox --kit ./sbx-sshd-v1 .` のように対話 shell 付きで起動する構成では、SSH 接続と VS Code Remote SSH 接続は成功した。

一方で、`-d` を付けた detached 起動で、`shell -- -c 'exec /usr/sbin/sshd ...'` のように shell agent のメインコマンドを直接 `sshd` に差し替える方式は安定していない。VS Code 側のログでは TCP 接続後に即 reset されており、`sshd` が正常に起動していない、または SSH protocol を返せていない状態に見える。

そのため、現時点の推奨方針は以下。

- `sshd` 自体は kit の `commands.startup` で起動する
- `startup` は `background: true` にする
- `sbx run -d shell ...` は sandbox を detached で起動するためだけに使う
- shell agent の `-- -c 'exec sshd ...'` 方式には依存しない

## 重要な仕様・判断

### ポート公開

Docker Sandbox / `sbx` では、sandbox 作成時ではなく起動後に `sbx ports` でポートを公開する。

```bash
sbx ports v1-sandbox --publish 127.0.0.1:2222:2222/tcp4
```

この構成では以下の対応になる。

```text
host:    127.0.0.1:2222
sandbox: 0.0.0.0:2222
```

VS Code Remote SSH からは sandbox の内部 IP ではなく、ホスト側の `127.0.0.1:2222` に接続する。

### root 起動 sshd ではなく user 起動 sshd にした理由

最初は sandbox 内の `22/tcp` で root が `sshd` を起動し、`/etc/ssh/sshd_config_sbx` を使う想定だった。

しかし `commands.initFiles` で `/etc/ssh/sshd_config_sbx` を作ろうとしたところ、以下のエラーが出た。

```text
sh: 1: cannot create /etc/ssh/sshd_config_sbx: Permission denied
```

`initFiles` は root 書き込みには向かないため、VS Code Remote SSH 用途では、`sshd` を `agent` ユーザー権限で動かし、設定ファイル類をすべて `/home/agent` 配下に寄せる方針に変更した。

### user 権限で sshd を動かす場合の制約

非 root で `sshd` を動かすため、以下の点に注意する。

- sandbox 内の待受ポートは 22 ではなく 1024 以上にする
  - 現在は `2222`
- `HostKey` は `/etc/ssh` ではなく `/home/agent/.ssh/sshd/` 配下に置く
- `PidFile` も `/home/agent/.ssh/sshd/sshd.pid` にする
- `UsePAM no` にする
- `AuthorizedKeysFile` は `/home/agent/.ssh/authorized_keys` を明示する
- `AllowUsers agent` にする

## 現在の kit 案

ディレクトリ例:

```text
sbx-sshd-v1/
└── spec.yaml
```

`sbx-sshd-v1/spec.yaml` の推奨形。

```yaml
schemaVersion: "1"
kind: mixin
name: sshd-user
displayName: SSH Server as agent
description: Start OpenSSH server as agent for VS Code Remote SSH

commands:
  install:
    - command: |
        set -eux

        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server

        install -d -m 700 -o agent -g agent /home/agent/.ssh
        install -d -m 700 -o agent -g agent /home/agent/.ssh/sshd

        if [ ! -f /home/agent/.ssh/sshd/ssh_host_ed25519_key ]; then
          sudo -u agent ssh-keygen -t ed25519 -N '' -f /home/agent/.ssh/sshd/ssh_host_ed25519_key
        fi

        chown -R agent:agent /home/agent/.ssh
        chmod 700 /home/agent/.ssh
        chmod 700 /home/agent/.ssh/sshd
        chmod 600 /home/agent/.ssh/sshd/ssh_host_ed25519_key
        chmod 644 /home/agent/.ssh/sshd/ssh_host_ed25519_key.pub
      user: "0"
      description: Install OpenSSH and create user-owned host key

  initFiles:
    - path: /home/agent/.ssh/authorized_keys
      content: |
        ssh-rsa AAAA...REPLACE_WITH_PUBLIC_KEY... user@example
      mode: "0600"
      onlyIfMissing: true
      description: Authorized SSH key for agent user

    - path: /home/agent/.ssh/sshd_config
      content: |
        Port 2222
        ListenAddress 0.0.0.0

        HostKey /home/agent/.ssh/sshd/ssh_host_ed25519_key
        PidFile /home/agent/.ssh/sshd/sshd.pid

        PermitRootLogin no
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PubkeyAuthentication yes
        UsePAM no

        AuthorizedKeysFile /home/agent/.ssh/authorized_keys
        AllowUsers agent

        PubkeyAcceptedAlgorithms +ssh-rsa,rsa-sha2-256,rsa-sha2-512
        HostbasedAcceptedAlgorithms +ssh-rsa,rsa-sha2-256,rsa-sha2-512

        X11Forwarding no
        AllowTcpForwarding yes
        PermitUserEnvironment no

        Subsystem sftp /usr/lib/openssh/sftp-server
      mode: "0600"
      onlyIfMissing: true
      description: User-level sshd config

  startup:
    - command: ["/usr/sbin/sshd", "-D", "-e", "-f", "/home/agent/.ssh/sshd_config"]
      user: "1000"
      background: true
      description: Start SSH server as agent
```

### 補足: RSA 公開鍵について

ユーザーは `~/.ssh/id_rsa.pub` の `ssh-rsa ...` を `authorized_keys` に貼っている。

画像上で出た `ED25519 key` の確認は、クライアント公開鍵ではなくサーバー側の host key 確認であり、パスワード要求ではなかった。

RSA 鍵を使うため、`sshd_config` に以下を追加している。

```sshconfig
PubkeyAcceptedAlgorithms +ssh-rsa,rsa-sha2-256,rsa-sha2-512
HostbasedAcceptedAlgorithms +ssh-rsa,rsa-sha2-256,rsa-sha2-512
```

ただし、長期的には `ed25519` のユーザー鍵へ移行する方がよい。

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

## `~/.ssh/config` 例

VS Code Remote SSH は直接 `agent@127.0.0.1:2222` を指定するより、SSH config の alias を使う方が安定する。

```sshconfig
Host sbx-v1
    HostName 127.0.0.1
    Port 2222
    User agent
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
```

sandbox を頻繁に作り直す場合、host key が毎回変わって known_hosts mismatch が起きることがある。その場合は開発用限定で以下も検討する。

```sshconfig
Host sbx-v1
    HostName 127.0.0.1
    Port 2222
    User agent
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

または手動で削除する。

```bash
ssh-keygen -R "[127.0.0.1]:2222"
```

## 成功した接続手順

1. sandbox を起動

```bash
sbx run shell --name v1-sandbox --kit ./sbx-sshd-v1 .
```

2. ポート公開

```bash
sbx ports v1-sandbox --publish 127.0.0.1:2222:2222/tcp4
```

3. 初回の host key 確認

```bash
ssh -p 2222 agent@127.0.0.1
```

表示されたら `Enter` ではなく `yes` と入力する。

```text
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

4. VS Code Remote SSH

```bash
code --remote ssh-remote+sbx-v1 "$(pwd)"
```

または直接指定。

```bash
code --remote ssh-remote+agent@127.0.0.1:2222 "$(pwd)"
```

## 発生した問題と解釈

### 1. `/etc/ssh/sshd_config_sbx` が作れない

エラー:

```text
ERROR: failed to create sandbox: request failed: 500 Internal Server Error: create sandbox container: run container: start container: started hook: kit "sshd": commands.initFiles[1] (/etc/ssh/sshd_config_sbx): exited 2 after 5ms
  ── captured output ──
  sh: 1: cannot create /etc/ssh/sshd_config_sbx: Permission denied
```

解釈:

- `initFiles` で `/etc` 配下に書こうとして失敗
- root 書き込みしたいファイルは `commands.install` で作る必要がある
- ただし今回は方針変更し、`/home/agent` 配下に寄せた

### 2. VS Code の host key 確認で止まる

ログ:

```text
The authenticity of host '[127.0.0.1]:2222' can't be established.
ED25519 key fingerprint is: SHA256:...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
Host key verification failed.
```

解釈:

- これはパスワード要求ではない
- `authorized_keys` の問題でもない
- 初回は `yes` を入力して known_hosts に登録する必要がある
- VS Code の askpass 上で空応答またはキャンセル扱いになったため失敗した

対処:

```bash
ssh -p 2222 agent@127.0.0.1
# yes と入力
```

### 3. `-d` 付きで shell agent の main command を sshd にしたら reset される

VS Code ログ:

```text
kex_exchange_identification: read: Connection reset by peer
Connection reset by 127.0.0.1 port 2222
```

解釈:

- SSH handshake 前に切断されている
- 公開鍵認証の問題ではない
- `sshd` が起動していない、または即終了している可能性が高い
- `sbx run -d shell ... -- -c 'exec /usr/sbin/sshd ...'` の引数渡しが detached 時に期待通りでない可能性がある

対処方針:

- `shell -- -c 'exec sshd ...'` 方式は避ける
- kit の `commands.startup` に `background: true` で `sshd` 起動を置く

## detached 起動で試すべき構成

`startup` を含む kit にした上で、次を試す。

```bash
sbx rm v1-sandbox 2>/dev/null || true

sbx run -d shell \
  --name v1-sandbox \
  --kit ./sbx-sshd-v1 \
  .

sbx ports v1-sandbox --publish 127.0.0.1:2222:2222/tcp4
```

確認:

```bash
sbx exec v1-sandbox ps aux | grep '[s]shd'
sbx exec v1-sandbox ss -ltnp | grep 2222
ssh -vvv -i ~/.ssh/id_rsa -o IdentitiesOnly=yes -p 2222 agent@127.0.0.1
```

期待される `ssh -vvv` のログ:

```text
Offering public key: .../.ssh/id_rsa
Server accepts key
Authenticated to 127.0.0.1
```

## 起動スクリプト案

`start-sbx-vscode.sh` のようなスクリプトを作る想定。

```bash
#!/usr/bin/env bash
set -euo pipefail

SANDBOX_NAME="${SANDBOX_NAME:-v1-sandbox}"
HOST_PORT="${HOST_PORT:-2222}"
REMOTE_PORT="${REMOTE_PORT:-2222}"
KIT_DIR="${KIT_DIR:-./sbx-sshd-v1}"
WORKDIR_PATH="${WORKDIR_PATH:-$(pwd)}"
SSH_HOST_ALIAS="${SSH_HOST_ALIAS:-sbx-v1}"

sbx rm "$SANDBOX_NAME" >/dev/null 2>&1 || true

sbx run -d shell \
  --name "$SANDBOX_NAME" \
  --kit "$KIT_DIR" \
  "$WORKDIR_PATH"

sbx ports "$SANDBOX_NAME" --publish "127.0.0.1:${HOST_PORT}:${REMOTE_PORT}/tcp4"

# Optional readiness check
for i in $(seq 1 30); do
  if ssh -o BatchMode=yes -o ConnectTimeout=1 -p "$HOST_PORT" agent@127.0.0.1 true >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

code --remote "ssh-remote+${SSH_HOST_ALIAS}" "$WORKDIR_PATH"
```

注意:

- `BatchMode=yes` にすると host key 未登録・鍵不一致の場合は失敗する
- 初回のみ事前に `ssh -p 2222 agent@127.0.0.1` で `yes` しておく
- sandbox 作り直し時の host key mismatch に備えて、必要なら `ssh-keygen -R "[127.0.0.1]:2222"` を入れる
- ただし自動削除は安全性と利便性のトレードオフ

## Codex への実装依頼内容

以下を実装・検証してほしい。

1. `sbx-sshd-v1/spec.yaml` を整理する
   - `agent` ユーザーで `sshd` を起動
   - `Port 2222`
   - `HostKey` / `PidFile` / `AuthorizedKeysFile` は `/home/agent/.ssh` 配下
   - `UsePAM no`
   - `PasswordAuthentication no`
   - RSA 公開鍵を使えるように `PubkeyAcceptedAlgorithms` を含める
   - `commands.startup` で `sshd` を `background: true` 起動する

2. `start-sbx-vscode.sh` を作成する
   - 既存 sandbox を必要に応じて削除
   - `sbx run -d shell --name ... --kit ... .`
   - `sbx ports ... --publish 127.0.0.1:2222:2222/tcp4`
   - SSH readiness check
   - `code --remote ssh-remote+sbx-v1 "$(pwd)"`

3. `~/.ssh/config` 例を README に書く
   - `Host sbx-v1`
   - `HostName 127.0.0.1`
   - `Port 2222`
   - `User agent`
   - `IdentityFile ~/.ssh/id_rsa`
   - `IdentitiesOnly yes`
   - `StrictHostKeyChecking accept-new`

4. デバッグコマンドを README に書く
   - `sbx exec v1-sandbox ps aux | grep '[s]shd'`
   - `sbx exec v1-sandbox ss -ltnp | grep 2222`
   - `ssh -vvv -i ~/.ssh/id_rsa -o IdentitiesOnly=yes -p 2222 agent@127.0.0.1`
   - `ssh-keygen -R "[127.0.0.1]:2222"`

5. 可能なら host port の自動選択を入れる
   - 例: macOS なら Python や `lsof` で空きポートを探す
   - ただし `~/.ssh/config` の更新と VS Code alias の扱いが必要になる

## 未解決・要確認

- `sbx run -d shell ... -- -c 'exec sshd ...'` が detached でうまくいかない正確な理由
  - 現状は使わない方針
- `sbx exec` で detached sandbox 内の `ps` / `ss` が確認できるか
- `startup.background: true` の sshd が `sbx run -d shell` でも期待通り生存するか
- sandbox 作り直し時の known_hosts 問題をどこまで自動化するか
- 将来的に `kind: sandbox` の custom entrypoint へ移行するか

## 作業時の最小テスト

```bash
sbx rm v1-sandbox 2>/dev/null || true
sbx run -d shell --name v1-sandbox --kit ./sbx-sshd-v1 .
sbx ports v1-sandbox --publish 127.0.0.1:2222:2222/tcp4

sbx exec v1-sandbox ps aux | grep '[s]shd'
sbx exec v1-sandbox ss -ltnp | grep 2222

ssh -vvv -i ~/.ssh/id_rsa -o IdentitiesOnly=yes -p 2222 agent@127.0.0.1
code --remote ssh-remote+sbx-v1 "$(pwd)"
```
