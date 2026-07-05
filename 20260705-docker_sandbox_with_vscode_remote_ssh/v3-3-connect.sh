#!/usr/bin/env bash
set -euo pipefail

SBX_SSH_USER="${SBX_SSH_USER:-agent}"
SBX_SSH_PORT="${SBX_SSH_PORT:-2222}"
WORKDIR_PATH="${WORKDIR_PATH:-$(pwd)}"

code --remote "ssh-remote+${SBX_SSH_USER}@127.0.0.1:${SBX_SSH_PORT}" "${WORKDIR_PATH}"
