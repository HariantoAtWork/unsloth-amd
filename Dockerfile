FROM ubuntu:24.04

# Match PyTorch / Unsloth supported ROCm stacks; override when bumping host ROCm.
ARG ROCM_VERSION=7.2.3

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/root/.local/bin:${PATH}"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
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
    apt-get update; \
    apt-get install -y --no-install-recommends \
        rocm-core \
        rocminfo \
        rocm-smi \
        amd-container-toolkit; \
    rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
