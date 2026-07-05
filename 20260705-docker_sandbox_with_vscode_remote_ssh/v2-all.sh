#!/bin/bash
set -xe

# シェルの起動は -d でバックグラウンドで実行
sbx run -d shell \
  --name v2-sandbox \
  --kit ./sbx-sshd-v2 \
  .

sbx ports v2-sandbox --publish 127.0.0.1:2222:2222/tcp4

code --remote ssh-remote+agent@127.0.0.1:2222 "$(pwd)"
