#!/usr/bin/env bash
# First-boot: download Ciru Halo Agent bundle + install pinned ROCm10 runtime,
# then launch the vision OpenAI-compatible server (serve-vision).
set -euo pipefail

export PATH="/root/.local/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:${PATH}}"

BUNDLE_ROOT="${CIRU_BUNDLE_ROOT:-/opt/ciru-halo-agent}"
RUNTIME_ROOT="${ORNITH_RUNTIME_ROOT:-/opt/ciru-runtime}"
HF_REPO="${HF_REPO:-jcbtc/Ornith1.5-Ciru-Halo-Agent-vllm-strix-halo}"
HOST="${CIRU_HOST:-0.0.0.0}"
PORT="${CIRU_PORT:-8000}"
MARKER="${RUNTIME_ROOT}/.docker-runtime-complete"

mkdir -p "${BUNDLE_ROOT}" "$(dirname "${RUNTIME_ROOT}")"

_have_bundle() {
    [[ -x "${BUNDLE_ROOT}/bundle/serve-vision.sh" ]] \
        && [[ -d "${BUNDLE_ROOT}/bundle/models/target" ]] \
        && [[ -f "${BUNDLE_ROOT}/runtime/INSTALL-ORNITH-RUNTIME.sh" ]]
}

_download_bundle() {
    if [[ "${CIRU_SKIP_DOWNLOAD:-0}" == "1" ]]; then
        echo "ERROR: Ciru bundle missing under ${BUNDLE_ROOT} and CIRU_SKIP_DOWNLOAD=1" >&2
        exit 1
    fi
    echo "==> Downloading ${HF_REPO} into ${BUNDLE_ROOT}"
    echo "    (model assets ~24 GB; allow 60 GB+ free disk per Ciru INSTALL.md)"
    # Download into the mount root. huggingface_hub writes files in-place.
    uvx --from huggingface_hub hf download \
        "${HF_REPO}" \
        --local-dir "${BUNDLE_ROOT}"
}

_install_runtime() {
    if [[ -f "${MARKER}" && -x "${RUNTIME_ROOT}/venv/bin/python" && -f "${RUNTIME_ROOT}/runtime-env.sh" ]]; then
        echo "==> Ciru runtime already installed at ${RUNTIME_ROOT}"
        return 0
    fi
    if [[ -e "${RUNTIME_ROOT}" && ! -f "${MARKER}" ]]; then
        echo "ERROR: ${RUNTIME_ROOT} exists but is incomplete (no ${MARKER})." >&2
        echo "       Remove that volume/path and restart so INSTALL-ORNITH-RUNTIME.sh can run." >&2
        exit 1
    fi
    echo "==> Installing Ciru Ornith runtime (ROCm 10 / PyTorch rocm10 / vLLM wheels)"
    bash "${BUNDLE_ROOT}/runtime/INSTALL-ORNITH-RUNTIME.sh" "${RUNTIME_ROOT}"
    touch "${MARKER}"
}

_ensure_devices() {
    if [[ ! -e /dev/kfd || ! -d /dev/dri ]]; then
        echo "WARNING: /dev/kfd or /dev/dri missing — GPU access required for Ciru (gfx1151)." >&2
        echo "         Pass devices: [/dev/kfd, /dev/dri] in Compose (same as unsloth-amd)." >&2
    fi
}

# Allow overriding the command (bash, serve.sh text-only, etc.).
if [[ "${1:-}" != "serve-vision" && "${1:-}" != "serve" && -n "${1:-}" ]]; then
    exec "$@"
fi

PROFILE="${1:-serve-vision}"
shift || true

_ensure_devices

if ! _have_bundle; then
    _download_bundle
fi
if ! _have_bundle; then
    echo "ERROR: bundle incomplete after download under ${BUNDLE_ROOT}" >&2
    exit 1
fi

export ORNITH_RUNTIME_ROOT="${RUNTIME_ROOT}"
_install_runtime

# Writable cache next to the bundle (prefix / AITER JIT).
mkdir -p "${BUNDLE_ROOT}/bundle/cache"

case "${PROFILE}" in
    serve-vision)
        echo "==> Starting Ciru serve-vision on ${HOST}:${PORT} (model id: ciru-halo-agent)"
        exec bash "${BUNDLE_ROOT}/bundle/serve-vision.sh" \
            --host "${HOST}" \
            --port "${PORT}" \
            "$@"
        ;;
    serve)
        echo "==> Starting Ciru text-only serve.sh on ${HOST}:${PORT}"
        exec bash "${BUNDLE_ROOT}/bundle/serve.sh" \
            --host "${HOST}" \
            --port "${PORT}" \
            "$@"
        ;;
    *)
        echo "ERROR: unknown profile '${PROFILE}' (use serve-vision or serve)" >&2
        exit 2
        ;;
esac
