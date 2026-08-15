# Why Unsloth is installed in the entrypoint (not the Dockerfile)

## Short answer

`docker build` / the Dockerfile only prepare the **hosting environment** (Ubuntu, ROCm apt stack, Bun, entrypoint/Studio scripts). They do **not** install Unsloth.

Unsloth is installed the **first time a container starts**, by `docker-entrypoint.sh`, which downloads and runs `https://unsloth.ai/install.sh` (under `expect` so the “Start Studio now?” prompt is answered `n`).

## Why not bake it into the image?

### 1. The installer needs the GPU

`install.sh` (and Unsloth’s stack detection) expects real AMD device nodes — typically `/dev/kfd` and `/dev/dri` — plus ROCm tools on `PATH` (`rocminfo`, etc.).

Those devices are attached at **run** time via Compose `devices:` (e.g. `/dev/kfd`, `/dev/dri`). A normal `docker build` does **not** see them, so a build-time install tends to pick the wrong stack (e.g. CPU PyTorch) or fail GPU detection.

That is why the entrypoint talks about reinstall “needs GPU /dev nodes”, and why Compose passes the DRM/KFD devices into every service.

### 2. This host needs a post-install torch pin

Upstream `install.sh` currently pulls a newer torch/ROCm combo that **SIGSEGVs on gfx1151** (Radeon 8060S). After install, `docker-studio-pinned.sh` re-pins torch/torchvision to the verified-good AMD gfx1151 wheels (see Dockerfile comments / image tag).

Doing install + pin at **startup** keeps that fix next to the GPU and the volume-backed venv, instead of freezing a fragile, GPU-specific install into every image rebuild.

### 3. Version can live on a shared volume

Because install is runtime + volume-backed (`/opt/unsloth-install`), several containers can share **one** Unsloth version without baking a multi‑GB venv into the image. See [Volume layout](Volume-layout.md).

## What `image:` actually gives you

Planner/builder use the same `image:` as the main service. That shares:

- ROCm userspace in the image  
- entrypoint / Studio / torch-pin scripts  

It does **not** share Unsloth itself until those containers also mount the shared `unsloth-install` volume (or you later bake Unsloth into the Dockerfile).

## Related files

- `Dockerfile` — base image; explicitly does not run `install.sh`
- `docker-entrypoint.sh` — `~/.unsloth` → install volume; first-boot installer
- `docker-studio-pinned.sh` (in the Dockerfile) — gfx1151 torch pin, then Studio
- `docker-compose.yml` — GPU devices + install/data volumes
- [Updating Unsloth](Update-Unsloth.md) — paste official `curl | sh` inside `unsloth-amd`
