#!/usr/bin/env bash
set -euo pipefail

export PATH="/root/.local/bin:${PATH}"

MARKER="${HOME}/.unsloth/.docker-install-complete"
mkdir -p "$(dirname "${MARKER}")"

if [[ ! -f "${MARKER}" ]]; then
    echo "==> First start: running https://unsloth.ai/install.sh (expects AMD GPU via /dev/dri and /dev/kfd)"
    curl -fsSL https://unsloth.ai/install.sh | sh
    touch "${MARKER}"
fi

exec "$@"
