#!/usr/bin/env bash
# First-boot: download Ciru Halo Agent bundle + install pinned ROCm10 runtime,
# then launch the vision OpenAI-compatible server (serve-vision).
set -euo pipefail

export PATH="/root/.local/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:${PATH}}"

BUNDLE_ROOT="${CIRU_BUNDLE_ROOT:-/opt/ciru-halo-agent}"
# Install into a *subdir* of the volume. Ciru's installer refuses any existing
# path, and a Docker volume mount always creates /opt/ciru-runtime.
RUNTIME_VOLUME="${CIRU_RUNTIME_VOLUME:-/opt/ciru-runtime}"
RUNTIME_ROOT="${ORNITH_RUNTIME_ROOT:-${RUNTIME_VOLUME}/installed}"
HF_REPO="${HF_REPO:-jcbtc/Ornith1.5-Ciru-Halo-Agent-vllm-strix-halo}"
HOST="${CIRU_HOST:-0.0.0.0}"
PORT="${CIRU_PORT:-8000}"
MARKER="${RUNTIME_ROOT}/.docker-runtime-complete"

mkdir -p "${BUNDLE_ROOT}" "${RUNTIME_VOLUME}"

_have_bundle() {
    # HF hub does not preserve +x; only require the files to exist.
    [[ -f "${BUNDLE_ROOT}/bundle/serve-vision.sh" ]] \
        && [[ -f "${BUNDLE_ROOT}/bundle/serve.sh" ]] \
        && [[ -d "${BUNDLE_ROOT}/bundle/models/target" ]] \
        && [[ -f "${BUNDLE_ROOT}/runtime/INSTALL-ORNITH-RUNTIME.sh" ]]
}

_fix_bundle_scripts() {
    chmod +x \
        "${BUNDLE_ROOT}/bundle/serve-vision.sh" \
        "${BUNDLE_ROOT}/bundle/serve.sh" \
        "${BUNDLE_ROOT}/bundle/packaging/serve.sh" \
        "${BUNDLE_ROOT}/runtime/INSTALL-ORNITH-RUNTIME.sh" \
        "${BUNDLE_ROOT}/runtime/INSTALL-RUNTIME.sh" \
        2>/dev/null || true
}

_download_bundle() {
    if [[ "${CIRU_SKIP_DOWNLOAD:-0}" == "1" ]]; then
        echo "ERROR: Ciru bundle missing under ${BUNDLE_ROOT} and CIRU_SKIP_DOWNLOAD=1" >&2
        exit 1
    fi
    echo "==> Downloading ${HF_REPO} into ${BUNDLE_ROOT}"
    echo "    (model assets ~24 GB; allow 60 GB+ free disk per Ciru INSTALL.md)"
    if [[ -n "${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}" ]]; then
        export HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN}}"
        echo "    using HF_TOKEN for authenticated Hub downloads"
    else
        echo "    tip: set HF_TOKEN for higher Hub rate limits (optional; not required for this public repo)"
    fi
    # Download into the mount root. huggingface_hub writes files in-place.
    uvx --from huggingface_hub hf download \
        "${HF_REPO}" \
        --local-dir "${BUNDLE_ROOT}"
}

_runtime_ready() {
    [[ -x "${RUNTIME_ROOT}/venv/bin/python" ]] \
        && "${RUNTIME_ROOT}/venv/bin/python" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 14) else 1)' \
        && [[ -e "${RUNTIME_ROOT}/runtime-env.sh" ]]
}

_install_runtime() {
    if [[ -f "${MARKER}" ]] && _runtime_ready; then
        echo "==> Ciru runtime already installed at ${RUNTIME_ROOT}"
        return 0
    fi
    if [[ -e "${RUNTIME_ROOT}" ]]; then
        # Partial install, or venv python symlink broken after image recreate
        # (uv keeps CPython under ~/.local/share, outside this volume).
        echo "==> Removing incomplete/broken runtime at ${RUNTIME_ROOT}"
        rm -rf "${RUNTIME_ROOT}"
    fi
    echo "==> Installing Ciru Ornith runtime into ${RUNTIME_ROOT}"
    echo "    (ROCm 10 / PyTorch rocm10 / vLLM wheels — several GB, takes a while)"
    bash "${BUNDLE_ROOT}/runtime/INSTALL-ORNITH-RUNTIME.sh" "${RUNTIME_ROOT}"
    if ! _runtime_ready; then
        echo "ERROR: runtime install finished but python is not usable" >&2
        exit 1
    fi
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
    echo "       expected: bundle/serve-vision.sh, bundle/models/target/, runtime/INSTALL-ORNITH-RUNTIME.sh" >&2
    ls -la "${BUNDLE_ROOT}" "${BUNDLE_ROOT}/bundle" 2>&1 || true
    exit 1
fi

_fix_bundle_scripts

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
