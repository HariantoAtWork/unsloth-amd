FROM ubuntu:24.04

# Match PyTorch / Unsloth supported ROCm stacks; override when bumping host ROCm.
ARG ROCM_VERSION=7.2.3

ENV DEBIAN_FRONTEND=noninteractive \
    ROCM_PATH=/opt/rocm \
    PATH="/opt/rocm/bin:/root/.bun/bin:/root/.local/bin:${PATH}" \
    UNSLOTH_STUDIO_HOST=0.0.0.0 \
    UNSLOTH_STUDIO_PORT=8888

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
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-studio.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/docker-studio.sh"]