#!/bin/bash
# シェルの起動は -d にする
sbx run -d shell \
  --name v2-sandbox \
  --kit ./sbx-sshd-v2 \
  .
