#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/rocm/bin:/root/.local/bin:${PATH}"

UNSLOTH=""
for _c in "${HOME}/.local/bin/unsloth" "${HOME}/.unsloth/studio/unsloth_studio/bin/unsloth"; do
    if [[ -x "${_c}" ]]; then
        UNSLOTH="${_c}"
        break
    fi
done

if [[ -z "${UNSLOTH}" ]]; then
    echo "ERROR: unsloth not found. Remove ~/.unsloth/.docker-install-complete or volumes and recreate the container." >&2
    exit 127
fi

exec "${UNSLOTH}" studio \
    --host "${UNSLOTH_STUDIO_HOST:-0.0.0.0}" \
    --port "${UNSLOTH_STUDIO_PORT:-8888}"
