#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./v3-common.sh
source "${SCRIPT_DIR}/v3-common.sh"

SBX_SANDBOX_NAME="${SBX_SANDBOX_NAME:-v3-sandbox}"
WORKDIR_PATH="${WORKDIR_PATH:-$(pwd)}"

render_runtime_kit
trap cleanup_runtime_kit EXIT

sbx run -d shell \
  --name "${SBX_SANDBOX_NAME}" \
  --kit "${RUNTIME_KIT_DIR}" \
  "${WORKDIR_PATH}"
