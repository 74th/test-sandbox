#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./v3-common.sh
source "${SCRIPT_DIR}/v3-common.sh"

SBX_SANDBOX_NAME="${SBX_SANDBOX_NAME:-v3-sandbox}"
WORKDIR_PATH="${WORKDIR_PATH:-$(pwd)}"
SBX_SSH_PORT="${SBX_SSH_PORT:-2222}"
SBX_SSH_USER="${SBX_SSH_USER:-agent}"
SBX_WAIT_SECONDS="${SBX_WAIT_SECONDS:-30}"

render_runtime_kit
trap cleanup_runtime_kit EXIT

sbx run -d shell \
  --name "${SBX_SANDBOX_NAME}" \
  --kit "${RUNTIME_KIT_DIR}" \
  "${WORKDIR_PATH}"

sbx ports "${SBX_SANDBOX_NAME}" --publish "127.0.0.1:${SBX_SSH_PORT}:${SBX_INTERNAL_SSH_PORT}/tcp4"

if ! wait_for_ssh_port 127.0.0.1 "${SBX_SSH_PORT}" "${SBX_WAIT_SECONDS}"; then
  echo "SSH port did not become ready within ${SBX_WAIT_SECONDS} seconds." >&2
  exit 1
fi

code --remote "ssh-remote+${SBX_SSH_USER}@127.0.0.1:${SBX_SSH_PORT}" "${WORKDIR_PATH}"
