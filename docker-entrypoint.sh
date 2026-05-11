#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/rocm/bin:/root/.local/bin:${PATH}"
export DEBIAN_FRONTEND=noninteractive CI=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_INPUT=1

MARKER="${HOME}/.unsloth/.docker-install-complete"
mkdir -p "$(dirname "${MARKER}")"

# True if we can run Unsloth (shim on volume or Studio venv on volume).
_unsloth_usable() {
    command -v unsloth >/dev/null 2>&1 && return 0
    [[ -x "${HOME}/.local/bin/unsloth" ]] && return 0
    [[ -x "${HOME}/.unsloth/studio/unsloth_studio/bin/unsloth" ]] && return 0
    return 1
}

_run_installer() {
    echo "==> Downloading https://unsloth.ai/install.sh"
    _installer="$(mktemp)"
    trap 'rm -f "${_installer:-}"' EXIT
    curl -fsSL https://unsloth.ai/install.sh -o "${_installer}"

    echo "==> Running installer under expect (auto-answer Studio prompt)"
    export INSTALLER="${_installer}"
    expect <<'EXPECT'
set timeout -1
log_user 1
spawn sh $env(INSTALLER)
expect {
    -re {Start Unsloth Studio now\?} {
        send "n\r"
        exp_continue
    }
    eof
}
catch wait waitres
exit [lindex $waitres 3]
EXPECT

    rm -f "${_installer}"
    trap - EXIT
}

if [[ "${UNSLOTH_SKIP_AUTO_INSTALL:-0}" != "1" ]]; then
    # Marker lived on a volume but ~/.local was not — new container skipped install and had no shim.
    if [[ -f "${MARKER}" ]] && ! _unsloth_usable; then
        echo "==> Install marker exists but unsloth is missing; re-running installer (needs GPU /dev nodes)"
        rm -f "${MARKER}"
    fi

    if [[ ! -f "${MARKER}" ]]; then
        _run_installer
        touch "${MARKER}"
    fi
fi

exec "$@"
