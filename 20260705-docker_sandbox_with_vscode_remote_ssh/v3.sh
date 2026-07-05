#!/usr/bin/env bash
# v3.sh
# 公開鍵を検出して、spec.yamlをsedで置換して埋め込む
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_TEMPLATE_PATH="${SCRIPT_DIR}/sbx-sshd-v3/spec.yaml"
SBX_INTERNAL_SSH_PORT=2222

SBX_SANDBOX_NAME="${SBX_SANDBOX_NAME:-v3-sandbox}"
WORKDIR_PATH="${WORKDIR_PATH:-$(pwd)}"
SBX_SSH_PORT="${SBX_SSH_PORT:-2222}"
SBX_SSH_USER="${SBX_SSH_USER:-agent}"
SBX_WAIT_SECONDS="${SBX_WAIT_SECONDS:-30}"

resolve_public_key_path() {
  if [[ -n "${PUBLIC_KEY_PATH:-}" ]]; then
    printf '%s\n' "${PUBLIC_KEY_PATH}"
    return 0
  fi

  local candidate
  for candidate in "${HOME}/.ssh/id_ed25519.pub" "${HOME}/.ssh/id_rsa.pub"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  echo "No public key found. Set PUBLIC_KEY_PATH to your *.pub file." >&2
  return 1
}

read_public_key() {
  local public_key_path="$1"

  if [[ ! -f "${public_key_path}" ]]; then
    echo "Public key file not found: ${public_key_path}" >&2
    return 1
  fi

  local public_key
  public_key="$(sed -n '1p' "${public_key_path}" | tr -d '\r')"

  if [[ -z "${public_key}" ]]; then
    echo "Public key file is empty: ${public_key_path}" >&2
    return 1
  fi

  printf '%s\n' "${public_key}"
}

escape_for_sed() {
  printf '%s' "$1" | sed -e 's/[|&\\]/\\&/g'
}

render_runtime_kit() {
  local public_key_path public_key escaped_public_key

  public_key_path="$(resolve_public_key_path)"
  public_key="$(read_public_key "${public_key_path}")"
  escaped_public_key="$(escape_for_sed "${public_key}")"

  RUNTIME_KIT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sbx-sshd-v3.XXXXXX")"
  RUNTIME_KIT_DIR="${RUNTIME_KIT_ROOT}/sbx-sshd-v3"
  mkdir -p "${RUNTIME_KIT_DIR}"

  sed "s|__AUTHORIZED_KEY__|${escaped_public_key}|" "${KIT_TEMPLATE_PATH}" > "${RUNTIME_KIT_DIR}/spec.yaml"

  echo "Using public key: ${public_key_path}" >&2
}

cleanup_runtime_kit() {
  if [[ -n "${RUNTIME_KIT_ROOT:-}" && -d "${RUNTIME_KIT_ROOT}" ]]; then
    rm -rf "${RUNTIME_KIT_ROOT}"
  fi
}

wait_for_ssh_port() {
  local host="${1:-127.0.0.1}"
  local port="${2:-2222}"
  local timeout_seconds="${3:-30}"
  local elapsed=0

  while (( elapsed < timeout_seconds )); do
    if bash -lc "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1; then
      return 0
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

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
