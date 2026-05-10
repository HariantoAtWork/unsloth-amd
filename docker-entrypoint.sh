#!/usr/bin/env bash
set -euo pipefail

# ROCm CLIs live under /opt/rocm/bin; install.sh uses `command -v rocminfo` / amd-smi.
export PATH="/opt/rocm/bin:/root/.local/bin:${PATH}"

MARKER="${HOME}/.unsloth/.docker-install-complete"
mkdir -p "$(dirname "${MARKER}")"

# Set UNSLOTH_SKIP_AUTO_INSTALL=1 to follow the manual install path (see README).
if [[ ! -f "${MARKER}" && "${UNSLOTH_SKIP_AUTO_INSTALL:-0}" != "1" ]]; then
    echo "==> First start: running https://unsloth.ai/install.sh (expects AMD GPU via /dev/dri and /dev/kfd)"
    curl -fsSL https://unsloth.ai/install.sh | sh
    touch "${MARKER}"
fi

exec "$@"
