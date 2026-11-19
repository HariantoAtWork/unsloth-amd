# Updating Unsloth

Unsloth is **not** in the Docker image and is **not** updated from the host checkout. `docker compose build` only rebuilds Ubuntu/ROCm/scripts. The package lives on the shared `unsloth-install` volume.

`~/.unsloth` inside the container is a symlink to `/opt/unsloth-install`, so the **official** installer line updates that volume. Planner and builder share it and pick up the new version after restart.

## Procedure

On the host, from this directory, stop the other Studios so they are not using the venv mid-upgrade, then open a shell in `unsloth-amd`:

```bash
docker compose stop unsloth-planner unsloth-builder
docker compose exec unsloth-amd bash
```

Inside that bash (not on the host), paste the same command as the Unsloth UI:

```bash
# Prefer skip-autostart so the installer does not fight the running Studio CMD
UNSLOTH_SKIP_AUTOSTART=1 curl -fsSL https://unsloth.ai/install.sh | sh
```

If the installer still asks **Start Unsloth Studio now?**, answer **n**. Studio is started by the container command, not by the installer.

Leave the container, then recreate so Studio reloads the new package (and the gfx1151 torch pin stays aligned with `UNSLOTH_TORCH`):

```bash
exit
docker compose up -d unsloth-amd
docker compose start unsloth-planner unsloth-builder
```

Do **not** `docker compose down` after an update — that is unnecessary. Watch pin/startup with `docker compose logs -f unsloth-amd`.

One-liner from the host (pipeline must stay inside the container):

```bash
docker compose exec unsloth-amd bash -lc 'UNSLOTH_SKIP_AUTOSTART=1 curl -fsSL https://unsloth.ai/install.sh | sh'
docker compose up -d unsloth-amd
```

## Do not

- Pipe `install.sh` on the **host**. This runs `curl` in the container and `sh` on the machine you typed it on:

  ```bash
  # WRONG — host shell owns `| sh`
  docker compose exec unsloth-amd curl -fsSL https://unsloth.ai/install.sh | sh
  ```

  The host parser splits on `|` before Docker sees it: left side is `docker compose exec … curl` (script bytes come back to your terminal); right side is bare `sh` (executes those bytes as **root on `/`**, not in the volume).

  Either `exec … bash` first (procedure above), or quote the whole pipeline as in the one-liner.

- `rm -rf ~/.unsloth` inside the container. That path is a symlink to the shared install volume.
- Expect **`docker compose build`** to bump Unsloth. The image does not contain the package.
- Answer **Y** to start Studio from the installer (it would fight the existing Studio process).

## After install: torch pin

From **2026.11.7**, upstream `install.sh` detects gfx1151 and installs `torch 2.11.0+rocm7.13.0` from AMD’s arch index (the stack that fixes earlier Strix `_grouped_mm` segfaults). Compose/`docker-studio-pinned.sh` pin to the same versions via `UNSLOTH_TORCH` / `UNSLOTH_TORCHVISION` so a restart does not roll back to `2.10`/`7.12`. Override those env vars if you need to pin differently. See [Why runtime Unsloth install](Why-runtime-Unsloth-install.md).

## Wipe and reinstall instead

To throw away the shared venv and let the **entrypoint** run `install.sh` on next start (same as first boot), see the README section **Resetting / reinstalling Unsloth**. That is destructive for all three services’ Unsloth version; per-service Studio data stays on the `*-data` volumes.
