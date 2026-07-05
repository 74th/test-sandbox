# Docker Sandbox + VS Code Remote SSH kit

`sbx-sshd-v3/spec.yaml` はそのまま repo に配布できるように、公開鍵本体を持たないテンプレート化された kit にしてあります。実行時に `v3-common.sh` がユーザーの公開鍵を読み取り、一時的な `spec.yaml` を生成して `sbx run --kit ...` に渡します。

## 使い方

最短では次で起動できます。

```bash
./v3-all.sh
```

既定では次の順で公開鍵を探します。

1. `PUBLIC_KEY_PATH`
2. `~/.ssh/id_ed25519.pub`
3. `~/.ssh/id_rsa.pub`

明示したい場合は次のように指定します。

```bash
PUBLIC_KEY_PATH="$HOME/.ssh/id_rsa.pub" ./v3-all.sh
```

内部では `sbx-sshd-v3/spec.yaml` をテンプレートとして使います。通常の起動入口は `v3-all.sh` です。

ステップごとに実行する場合:

```bash
./v3-1-create.sh
./v3-2-open_port.sh
./v3-3-connect.sh
```

## 変更できる環境変数

```bash
SBX_SANDBOX_NAME=v3-sandbox
WORKDIR_PATH=$(pwd)
SBX_SSH_PORT=2222
SBX_SSH_USER=agent
SBX_WAIT_SECONDS=30
PUBLIC_KEY_PATH=$HOME/.ssh/id_ed25519.pub
```

例:

```bash
SBX_SANDBOX_NAME=my-sbx SBX_SSH_PORT=2223 PUBLIC_KEY_PATH="$HOME/.ssh/id_rsa.pub" ./v3-all.sh
```

## 初回 SSH 接続

初回は host key 確認で止まることがあります。VS Code の前に一度次を実行すると分かりやすいです。

```bash
ssh -p 2222 agent@127.0.0.1
```

`yes` と入力して接続を許可してください。

`~/.ssh/config` を使う場合の例:

```sshconfig
Host sbx-v3
    HostName 127.0.0.1
    Port 2222
    User agent
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
```

RSA 鍵を使う場合は `IdentityFile ~/.ssh/id_rsa` に置き換えてください。kit 側では `ssh-rsa` / `rsa-sha2-*` も受け付けるようにしてあります。

## デバッグ

```bash
sbx exec v3-sandbox ps aux | grep '[s]shd'
sbx exec v3-sandbox ss -ltnp | grep 2222
ssh -vvv -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -p 2222 agent@127.0.0.1
ssh-keygen -R "[127.0.0.1]:2222"
```
