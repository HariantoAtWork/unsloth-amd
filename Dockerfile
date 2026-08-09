FROM ubuntu:24.04

# Match PyTorch / Unsloth supported ROCm stacks; override when bumping host ROCm.
ARG ROCM_VERSION=7.2.3

# Fresh Unsloth install.sh currently pulls torch 2.11+rocm7.13, which SIGSEGVs on
# gfx1151 (Radeon 8060S). Highest verified-good stack on this host is
# torch 2.10.0+rocm7.12.0 from AMD's gfx1151 wheel index (7.13 still segfaults).
# Image tag convention: harianto/unsloth-amd:1.0.0-torch2.10.0-rocm7.12.0
ARG UNSLOTH_TORCH=2.10.0+rocm7.12.0
ARG UNSLOTH_TORCHVISION=0.25.0+rocm7.12.0
ARG UNSLOTH_TORCH_INDEX=https://repo.amd.com/rocm/whl/gfx1151/

ENV DEBIAN_FRONTEND=noninteractive \
    ROCM_PATH=/opt/rocm \
    PATH="/opt/rocm/bin:/root/.bun/bin:/root/.local/bin:${PATH}" \
    UNSLOTH_STUDIO_HOST=0.0.0.0 \
    UNSLOTH_STUDIO_PORT=8888 \
    UNSLOTH_TORCH=${UNSLOTH_TORCH} \
    UNSLOTH_TORCHVISION=${UNSLOTH_TORCHVISION} \
    UNSLOTH_TORCH_INDEX=${UNSLOTH_TORCH_INDEX}

EXPOSE 8888

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        expect \
        unzip \
        wget \
        gnupg2 \
        git \
        cmake \
        build-essential \
        libcurl4-openssl-dev \
        pkg-config; \
    mkdir -p /etc/apt/keyrings; \
    wget -qO- "https://repo.radeon.com/rocm/rocm.gpg.key" \
        | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg; \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} noble main" \
        > /etc/apt/sources.list.d/rocm.list; \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amd-container-toolkit/apt/ noble main" \
        > /etc/apt/sources.list.d/amd-container-toolkit.list; \
    printf '%s\n' \
        'Package: *' \
        'Pin: release o=repo.radeon.com' \
        'Pin-Priority: 600' \
        > /etc/apt/preferences.d/rocm-pin-600; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        rocm-core \
        rocminfo \
        rocm-smi \
        amd-smi-lib \
        rocm-dev \
        hipblas-dev \
        rocblas-dev \
        amd-container-toolkit; \
    rm -rf /var/lib/apt/lists/*

# Install Bun and upgrade to the canary channel (main-branch builds).
RUN set -eux; \
    curl -fsSL https://bun.sh/install | bash; \
    bun upgrade --canary; \
    bun --revision

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker-studio.sh /usr/local/bin/docker-studio.sh

# After install.sh finishes, pin the gfx1151-safe torch stack, then start Studio.
COPY --chmod=755 <<'EOF' /usr/local/bin/docker-studio-pinned.sh
#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/rocm/bin:/root/.bun/bin:/root/.local/bin:${PATH}"

VENV="${HOME}/.unsloth/studio/unsloth_studio"
PY="${VENV}/bin/python"
MARKER="${HOME}/.unsloth/.docker-torch-pin-complete"
TORCH_SPEC="${UNSLOTH_TORCH:-2.10.0+rocm7.12.0}"
TV_SPEC="${UNSLOTH_TORCHVISION:-0.25.0+rocm7.12.0}"
INDEX="${UNSLOTH_TORCH_INDEX:-https://repo.amd.com/rocm/whl/gfx1151/}"

_prefer_wheel_rocm_libs() {
    local site
    site="$("${PY}" -c 'import site; print(site.getsitepackages()[0])')"
    local paths=()
    [[ -d "${site}/_rocm_sdk_core/lib" ]] && paths+=("${site}/_rocm_sdk_core/lib")
    [[ -d "${site}/_rocm_sdk_libraries_gfx1151/lib" ]] && paths+=("${site}/_rocm_sdk_libraries_gfx1151/lib")
    [[ -d "${site}/torch/lib" ]] && paths+=("${site}/torch/lib")
    if ((${#paths[@]})); then
        local joined
        joined="$(IFS=:; echo "${paths[*]}")"
        export LD_LIBRARY_PATH="${joined}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
        echo "==> Preferring wheel ROCm libs: ${joined}"
    fi
}

_pin_torch() {
    if [[ ! -x "${PY}" ]]; then
        echo "ERROR: Studio venv python missing at ${PY}" >&2
        return 1
    fi

    local current
    current="$("${PY}" -c 'import torch; print(torch.__version__)' 2>/dev/null || true)"
    if [[ "${current}" == "${TORCH_SPEC}" && -f "${MARKER}" ]]; then
        echo "==> Torch already pinned (${current})"
        return 0
    fi

    echo "==> Pinning torch to ${TORCH_SPEC} (was: ${current:-unknown})"
    echo "    index: ${INDEX}"

    # Drop mismatched TheRock/meta packages before installing the pinned gfx1151 stack.
    "${PY}" -m pip uninstall -y rocm rocm-sdk-core rocm-sdk-libraries-gfx1151 2>/dev/null || true

    "${PY}" -m pip install --upgrade \
        --index-url "${INDEX}" \
        --extra-index-url https://pypi.org/simple \
        "torch==${TORCH_SPEC}" \
        "torchvision==${TV_SPEC}"

    "${PY}" -c 'import torch; print("pinned torch", torch.__version__, "hip", torch.version.hip)'
    mkdir -p "$(dirname "${MARKER}")"
    printf '%s\n' "${TORCH_SPEC}" > "${MARKER}"
}

_pin_torch
_prefer_wheel_rocm_libs
exec /usr/local/bin/docker-studio.sh
EOF

RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-studio.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/docker-studio-pinned.sh"]
