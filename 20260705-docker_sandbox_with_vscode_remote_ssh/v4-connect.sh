#!/usr/bin/env bash
set -euo pipefail
set -x

REMOTE_SSH_FILE="${PWD}/.sbx_remote_ssh"
SBX_WAIT_SECONDS="${SBX_WAIT_SECONDS:-30}"

usage() {
  echo "Run ./v4-include.sh SANDBOX_NAME first." >&2
}

load_remote_ssh_file() {
  if [[ ! -f "${REMOTE_SSH_FILE}" ]]; then
    usage
    return 1
  fi

  # shellcheck disable=SC1090
  source "${REMOTE_SSH_FILE}"

  : "${SBX_SANDBOX_NAME:?Missing SBX_SANDBOX_NAME in .sbx_remote_ssh}"
  : "${SBX_SSH_PORT:?Missing SBX_SSH_PORT in .sbx_remote_ssh}"
  SBX_SSH_USER="${SBX_SSH_USER:-agent}"
  SBX_INTERNAL_SSH_PORT="${SBX_INTERNAL_SSH_PORT:-2222}"
}

ensure_sshd_running() {
  if sbx exec "${SBX_SANDBOX_NAME}" sh -lc 'pgrep -x sshd >/dev/null 2>&1'; then
    return 0
  fi

  sbx exec "${SBX_SANDBOX_NAME}" sh -lc 'command -v sshd >/dev/null 2>&1 && test -f /home/agent/.ssh/sshd_config && test -f /home/agent/.ssh/authorized_keys'

  sbx exec -u "${SBX_SSH_USER}" "${SBX_SANDBOX_NAME}" sh -lc '
    nohup /usr/sbin/sshd -D -f /home/agent/.ssh/sshd_config >/tmp/sbx-sshd.log 2>&1 </dev/null &
  ' >/dev/null
}

wait_for_ssh_port() {
  local host="$1"
  local port="$2"
  local timeout_seconds="$3"
  local elapsed=0

  while (( elapsed < timeout_seconds )); do
    if command -v nc >/dev/null 2>&1; then
      if nc -z -w 1 "${host}" "${port}" >/dev/null 2>&1; then
        return 0
      fi
    else
      if bash -lc "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1; then
        return 0
      fi
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

main() {
  load_remote_ssh_file

  sbx exec "${SBX_SANDBOX_NAME}" true >/dev/null
  ensure_sshd_running

  if ! sbx ports "${SBX_SANDBOX_NAME}" --publish "127.0.0.1:${SBX_SSH_PORT}:${SBX_INTERNAL_SSH_PORT}/tcp4" >/dev/null 2>&1; then
    echo "Port publish may already exist or may be blocked: ${SBX_SSH_PORT}" >&2
  fi

  if ! wait_for_ssh_port 127.0.0.1 "${SBX_SSH_PORT}" "${SBX_WAIT_SECONDS}"; then
    echo "SSH port ${SBX_SSH_PORT} did not become ready." >&2
    sbx exec "${SBX_SANDBOX_NAME}" sh -lc "ps aux | grep '[s]shd' || true" >&2 || true
    echo "If this host port is no longer usable, rerun ./v4-include.sh ${SBX_SANDBOX_NAME}." >&2
    exit 1
  fi

  code --remote "ssh-remote+${SBX_SSH_USER}@127.0.0.1:${SBX_SSH_PORT}" "$(pwd)"
}

main "$@"
