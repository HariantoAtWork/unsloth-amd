# Unsloth (AMD / ROCm) in Docker

Ubuntu 24.04 image with ROCm apt packages, GPU device passthrough, and the official Unsloth Studio installer.

## Requirements

- Linux host with an AMD GPU and a working ROCm/AMD stack on the **host** (this image does not install kernel drivers).
- Docker with Compose v2.
- For GPU access inside the container, the host must expose the same device nodes you pass in Compose (typically `/dev/dri` and `/dev/kfd`).

## Automatic first start (default)

From this directory:

```bash
docker compose up --build -d
```

On the **first** start, the entrypoint runs:

```bash
curl -fsSL https://unsloth.ai/install.sh | sh
```

A marker file is created at `~/.unsloth/.docker-install-complete` inside the container (backed by the `unsloth-home` volume) so this only runs once.

Check logs:

```bash
docker compose logs -f unsloth-amd
```

Open a shell after install:

```bash
docker compose exec unsloth-amd bash
```

Unsloth Studio’s venv (after a successful install) is under `/root/.unsloth/studio/.venv` by default. Ensure `PATH` includes `~/.local/bin` for the `unsloth` / `uv` shims the installer adds (the image already prepends `/root/.local/bin`).

## Manual install (skip automatic `install.sh`)

Set `UNSLOTH_SKIP_AUTO_INSTALL=1` so the entrypoint does **not** run the installer:

```bash
docker compose run --rm -e UNSLOTH_SKIP_AUTO_INSTALL=1 unsloth-amd bash
```

Or add under `services.unsloth-amd` in `docker-compose.yml`:

```yaml
environment:
  UNSLOTH_SKIP_AUTO_INSTALL: "1"
```

Then run the installer yourself when the GPU devices are available:

```bash
export PATH="/root/.local/bin:${PATH}"
curl -fsSL https://unsloth.ai/install.sh | sh
touch ~/.unsloth/.docker-install-complete
```

The final `touch` matches what the automatic path does; without it, every start would still behave like a “first boot” regarding the marker (optional if you keep `UNSLOTH_SKIP_AUTO_INSTALL=1` permanently).

## Fully manual Docker (no Compose)

Build:

```bash
docker build -t unsloth-amd:local --build-arg ROCM_VERSION=7.2.3 .
```

Run (adjust volume path if you want a bind mount instead of a named volume):

```bash
docker run --rm -it \
  --device /dev/dri \
  --device /dev/kfd \
  --shm-size=2g \
  -v unsloth-home:/root/.unsloth \
  unsloth-amd:local
```

Then either rely on the default entrypoint (automatic first install) or override it:

```bash
docker run --rm -it \
  --device /dev/dri \
  --device /dev/kfd \
  --shm-size=2g \
  -e UNSLOTH_SKIP_AUTO_INSTALL=1 \
  -v unsloth-home:/root/.unsloth \
  unsloth-amd:local \
  bash
```

## ROCm version in the image

The Dockerfile `ARG ROCM_VERSION` (default `7.2.3`) selects the ROCm apt suite used for `rocm-core` and related packages. Override when building:

```bash
docker build --build-arg ROCM_VERSION=7.2.3 -t unsloth-amd:local .
```

Align this with a ROCm stack that matches PyTorch wheels Unsloth can pull for your GPU.

## Resetting / reinstalling Unsloth

- Remove the marker and optionally wipe the volume:

  ```bash
  docker compose exec unsloth-amd rm -f /root/.unsloth/.docker-install-complete
  ```

- Or remove the named volume (destructive):

  ```bash
  docker compose down
  docker volume rm unsloth-home
  ```

Then start the stack again to trigger a fresh installer run (unless `UNSLOTH_SKIP_AUTO_INSTALL=1` is set).

## Troubleshooting

- **Installer chooses CPU PyTorch:** the container usually cannot see the GPU during `docker build`. Run the installer at **runtime** with `/dev/dri` and `/dev/kfd` passed through. Verify with `rocminfo` inside the container.
- **`/dev/dri` or `/dev/kfd` permission errors:** on some hosts you may need `group_add: [video, render]` or numeric supplementary GIDs matching the host; adjust Compose to match your udev setup.
- **OOM or dataloader issues:** `shm_size` is set to 2 GB in Compose; increase if needed.
