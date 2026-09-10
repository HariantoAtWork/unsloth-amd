# Unsloth (AMD / ROCm) in Docker

Ubuntu 24.04 image with ROCm apt packages, GPU device passthrough, and the official Unsloth Studio installer.

**Design notes (why entrypoint install, volume layout, updating Unsloth):** [docs/wiki/Home.md](docs/wiki/Home.md)

## Requirements

- Linux host with an AMD GPU and a working ROCm/AMD stack on the **host** (this image does not install kernel drivers).
- Docker with Compose v2.
- For GPU access inside the container, the host must expose the same device nodes you pass in Compose (typically `/dev/dri` and `/dev/kfd`).

## Automatic first start (default)

Image sources live under **`build/unsloth-amd/`** (one folder per image). **`bun run docker:build`** / **`docker compose -f docker-compose.build.yml build`** only create the image (Ubuntu + ROCm/apt stack in the Dockerfile). They do **not** run `install.sh` or install Unsloth. The Unsloth install runs the **first time a container starts** (entrypoint), not during the build — the installer needs GPU device nodes that exist at run time, not during `docker build`. Details: [Why runtime Unsloth install](docs/wiki/Why-runtime-Unsloth-install.md).

From this directory:

```bash
bun run docker:build
bun run docker:up
```

Or with Compose directly: `docker compose -f docker-compose.build.yml build` then `docker compose up -d`. Watch install progress with `docker compose logs -f unsloth-amd`.

On the **first** start, **`build/unsloth-amd/docker-entrypoint.sh`** **`curl`**s **`https://unsloth.ai/install.sh`** to a temp file and runs **`sh`** under **`expect`**. The installer’s final **`Start Unsloth Studio now? [Y/n]`** is read from **`/dev/tty`**, so piping **`n`** on stdin does not work; **expect** drives a pseudo-TTY and sends **`n`** so Studio is not started inside the installer (your **`CMD`** starts Studio). The image installs the **`expect`** package for this. Optional: **`build/unsloth-amd/patch.sh`** still documents the **`--no-launch`** sed/awk patch if you prefer not to use **expect**.

A marker is written at `/opt/unsloth-install/.docker-install-complete` (shared `unsloth-install` volume) so the full installer only runs once for the whole stack. Save data lives on per-service `*-data` volumes; see [Volume layout](docs/wiki/Volume-layout.md).

After install (and on later boots), the container runs **Unsloth Studio** bound to `0.0.0.0` so it can be reached from the host. By default Compose publishes **`8888`** (`http://localhost:8888`). Override the host/container port with `UNSLOTH_STUDIO_PORT` when invoking Compose (the same value is passed through to Studio).

Check logs:

```bash
docker compose logs -f unsloth-amd
```

Open a shell after install:

```bash
docker compose exec unsloth-amd bash
```

Unsloth Studio’s venv (after a successful install) lives under `/opt/unsloth-install/studio/unsloth_studio` (symlinked as `~/.unsloth/studio/unsloth_studio`). Ensure `PATH` includes `~/.local/bin` for the `unsloth` shim the entrypoint maintains.

To run a shell instead of Studio, override the command, for example: `docker compose run --rm unsloth-amd bash`.

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
docker build -t unsloth-amd:local --build-arg ROCM_VERSION=7.2.3 -f build/unsloth-amd/Dockerfile build/unsloth-amd
```

Run (adjust volume path if you want a bind mount instead of a named volume):

```bash
docker run --rm -it \
  --shm-size=2g \
  -p 8888:8888 \
  --device /dev/kfd \
  --device /dev/dri \
  -v unsloth-install:/opt/unsloth-install \
  -v unsloth-amd-data:/data/unsloth \
  --group-add video --group-add render \
  unsloth-amd:local
```

Then either rely on the default entrypoint (automatic first install) or override it:

```bash
docker run --rm -it \
  --shm-size=2g \
  -e UNSLOTH_SKIP_AUTO_INSTALL=1 \
  --device /dev/kfd \
  --device /dev/dri \
  -v unsloth-install:/opt/unsloth-install \
  -v unsloth-amd-data:/data/unsloth \
  --group-add video --group-add render \
  unsloth-amd:local \
  bash
```## ROCm version in the image

The Dockerfile `ARG ROCM_VERSION` (default `7.2.3`) selects the ROCm apt suite used for `rocm-core` and related packages. Override when building:

```bash
docker build --build-arg ROCM_VERSION=7.2.3 -t unsloth-amd:local -f build/unsloth-amd/Dockerfile build/unsloth-amd
```

Align this with a ROCm stack that matches PyTorch wheels Unsloth can pull for your GPU.

## Updating Unsloth

Unsloth lives on the shared `unsloth-install` volume, not in the image. Inside `unsloth-amd` bash, the official installer line is enough (`~/.unsloth` is a symlink to that volume):

```bash
docker compose stop unsloth-planner unsloth-builder
docker compose exec unsloth-amd bash
```

Then paste:

```bash
curl -fsSL https://unsloth.ai/install.sh | sh
```

Answer **n** to **Start Unsloth Studio now?**, `exit`, then `docker compose restart unsloth-amd` and `docker compose start unsloth-planner unsloth-builder`. Do **not** run `docker compose exec unsloth-amd curl … | sh` on the host (the host shell owns `| sh`). Full notes: [Updating Unsloth](docs/wiki/Update-Unsloth.md).

## Resetting / reinstalling Unsloth

- Remove the shared install marker (triggers reinstall on next start if the venv is also gone/broken):

  ```bash
  docker compose exec unsloth-amd rm -f /opt/unsloth-install/.docker-install-complete
  ```

- Or remove named volumes (destructive):

  ```bash
  docker compose down
  # Full Unsloth reinstall for all services:
  docker volume rm unsloth-install
  # One service's Studio state only (example):
  # docker volume rm unsloth-amd-data
  ```

Then start the stack again to trigger a fresh installer run (unless `UNSLOTH_SKIP_AUTO_INSTALL=1` is set). Volume map: [Volume layout](docs/wiki/Volume-layout.md).

## Troubleshooting

- **Installer chooses CPU PyTorch:** two common causes: (1) **ROCm tools not on `PATH` inside the image** — `install.sh` uses `command -v rocminfo`; this image prepends `/opt/rocm/bin`. (2) **GPU device nodes not visible in the container** — Compose passes `/dev/kfd` and `/dev/dri` via `devices:`. Rebuild the image after Dockerfile changes, then check:
  ```bash
  docker compose run --rm unsloth-amd bash -lc 'rocminfo | head -40'
  ```
  You should see a `Name: gfx…` GPU agent, not only the CPU. If you still get CPU wheels, remove the install marker (and optionally the `unsloth-install` volume) and bring the stack up again so `install.sh` re-runs with GPU visible.
- **`/dev/dri` or `/dev/kfd` permission errors:** Compose includes `group_add: [video, render]`; if ACLs or unusual GIDs persist on your host, add numeric supplementary GIDs that match the host’s `getent group video render` output.
- **`image:` alone does not install Unsloth:** planner/builder reuse the same image layers, but Unsloth lives on the shared `unsloth-install` volume. See [Why runtime Unsloth install](docs/wiki/Why-runtime-Unsloth-install.md).
- **OOM or dataloader issues:** `shm_size` is set to 2 GB in Compose; increase if needed.
