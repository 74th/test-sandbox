#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./v3-common.sh
source "${SCRIPT_DIR}/v3-common.sh"

SBX_SANDBOX_NAME="${SBX_SANDBOX_NAME:-v3-sandbox}"
SBX_SSH_PORT="${SBX_SSH_PORT:-2222}"

sbx ports "${SBX_SANDBOX_NAME}" --publish "127.0.0.1:${SBX_SSH_PORT}:${SBX_INTERNAL_SSH_PORT}/tcp4"
