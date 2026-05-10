#!/usr/bin/env bash
set -euo pipefail

# Default binds so published Docker ports work (see Dockerfile EXPOSE / compose ports).
export PATH="/opt/rocm/bin:/root/.local/bin:${PATH}"

exec unsloth studio \
    --host "${UNSLOTH_STUDIO_HOST:-0.0.0.0}" \
    --port "${UNSLOTH_STUDIO_PORT:-8888}"
