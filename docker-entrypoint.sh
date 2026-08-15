#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/rocm/bin:/root/.local/bin:${PATH}"
export DEBIAN_FRONTEND=noninteractive CI=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_INPUT=1

# Sibling layout (no nested Docker volume overlays):
#   INSTALL_ROOT  shared Unsloth version (venv, llama.cpp, helper venvs)
#   DATA_ROOT     per-service save data (auth, db, runs, API keys, last model)
#   ~/.unsloth    symlink → INSTALL_ROOT so `curl | sh` inside the container
#                 updates the volume (do not mount ~/.unsloth itself)
INSTALL_ROOT="${UNSLOTH_INSTALL_ROOT:-/opt/unsloth-install}"
DATA_ROOT="${UNSLOTH_DATA_ROOT:-/data/unsloth}"
UNSLOTH_HOME="${HOME}/.unsloth"
INSTALL_MARKER="${INSTALL_ROOT}/.docker-install-complete"
export TMPDIR="${TMPDIR:-${INSTALL_ROOT}/tmp}"
mkdir -p "${TMPDIR}"

_unsloth_bin() {
    local c
    for c in \
        "${INSTALL_ROOT}/studio/unsloth_studio/bin/unsloth" \
        "${UNSLOTH_HOME}/studio/unsloth_studio/bin/unsloth" \
        "${HOME}/.local/bin/unsloth"
    do
        if [[ -x "${c}" ]]; then
            printf '%s' "${c}"
            return 0
        fi
    done
    return 1
}

_unsloth_usable() {
    command -v unsloth >/dev/null 2>&1 && return 0
    _unsloth_bin >/dev/null 2>&1
}

# Drop per-service state that install.sh may have written into the shared install.
_purge_data_from_install() {
    local d f
    for d in auth exports outputs runs cache; do
        rm -rf "${INSTALL_ROOT}/studio/${d}"
    done
    rm -f "${INSTALL_ROOT}/studio/studio.db" "${INSTALL_ROOT}/studio/studio.pid"
    for f in .docker-api-key .docker-last-model.json .docker-watcher-api-key; do
        rm -f "${INSTALL_ROOT}/${f}"
    done
}

# ~/.unsloth → shared install; per-service data is linked from that tree to DATA_ROOT.
# Same /data/unsloth path in every container; each service mounts a different volume there.
_link_unsloth_layout() {
    local name f

    mkdir -p "${INSTALL_ROOT}/studio" "${INSTALL_ROOT}/llama.cpp" "${INSTALL_ROOT}/tmp" \
        "${DATA_ROOT}/studio" "${HOME}/.local/bin"

    if [[ -L "${UNSLOTH_HOME}" ]]; then
        rm -f "${UNSLOTH_HOME}"
    elif [[ -d "${UNSLOTH_HOME}" ]]; then
        rm -rf "${UNSLOTH_HOME}"
    fi
    ln -sfn "${INSTALL_ROOT}" "${UNSLOTH_HOME}"

    _purge_data_from_install

    for name in auth exports outputs runs cache; do
        mkdir -p "${DATA_ROOT}/studio/${name}"
        ln -sfn "${DATA_ROOT}/studio/${name}" "${INSTALL_ROOT}/studio/${name}"
    done
    for f in studio.db studio.pid; do
        ln -sfn "${DATA_ROOT}/studio/${f}" "${INSTALL_ROOT}/studio/${f}"
    done
    for f in .docker-api-key .docker-last-model.json .docker-watcher-api-key; do
        ln -sfn "${DATA_ROOT}/${f}" "${INSTALL_ROOT}/${f}"
    done

    if [[ -x "${INSTALL_ROOT}/studio/unsloth_studio/bin/unsloth" ]]; then
        ln -sfn "${INSTALL_ROOT}/studio/unsloth_studio/bin/unsloth" "${HOME}/.local/bin/unsloth"
    fi
}

_run_installer() {
    echo "==> Installing Unsloth into ${INSTALL_ROOT}"
    # Point ~/.unsloth at the shared install for the duration of install.sh so the
    # installer does not have to know about our split layout.
    if [[ -L "${UNSLOTH_HOME}" || -e "${UNSLOTH_HOME}" ]]; then
        rm -rf "${UNSLOTH_HOME}"
    fi
    ln -sfn "${INSTALL_ROOT}" "${UNSLOTH_HOME}"

    echo "==> Downloading https://unsloth.ai/install.sh"
    local _installer
    _installer="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '${_installer}'" EXIT
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

    _purge_data_from_install
    touch "${INSTALL_MARKER}"
}

_link_unsloth_layout

if [[ "${UNSLOTH_SKIP_AUTO_INSTALL:-0}" != "1" ]]; then
    if [[ -f "${INSTALL_MARKER}" ]] && ! _unsloth_usable; then
        echo "==> Install marker exists but unsloth is missing; re-running installer (needs GPU /dev nodes)"
        rm -f "${INSTALL_MARKER}"
    fi

    if [[ ! -f "${INSTALL_MARKER}" ]]; then
        if _unsloth_usable; then
            echo "==> Shared Unsloth install already present; skipping install.sh"
            touch "${INSTALL_MARKER}"
        else
            _run_installer
            # Re-link after install (installer left ~/.unsloth → INSTALL_ROOT).
            _link_unsloth_layout
        fi
    fi
fi

exec "$@"
