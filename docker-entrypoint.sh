#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/rocm/bin:/root/.local/bin:${PATH}"
export DEBIAN_FRONTEND=noninteractive CI=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_INPUT=1

MARKER="${HOME}/.unsloth/.docker-install-complete"
mkdir -p "$(dirname "${MARKER}")"

if [[ ! -f "${MARKER}" && "${UNSLOTH_SKIP_AUTO_INSTALL:-0}" != "1" ]]; then
    echo "==> Downloading https://unsloth.ai/install.sh"
    _installer="$(mktemp)"
    trap 'rm -f "${_installer:-}"' EXIT
    curl -fsSL https://unsloth.ai/install.sh -o "${_installer}"

    # install.sh reads "Start Unsloth Studio now?" from /dev/tty — piping stdin does not work.
    # expect(1) attaches a pty and sends "n" so Studio is not started inside the installer (CMD starts it).
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
    touch "${MARKER}"
fi

exec "$@"
