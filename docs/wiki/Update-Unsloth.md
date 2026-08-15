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
curl -fsSL https://unsloth.ai/install.sh | sh
```

When asked **Start Unsloth Studio now?**, answer **n**. Studio is started by the container command, not by the installer.

Leave the container, then restart so the gfx1151 torch pin re-applies:

```bash
exit
docker compose restart unsloth-amd
docker compose start unsloth-planner unsloth-builder
```

Do **not** `docker compose down` after an update — that is unnecessary. Watch pin/startup with `docker compose logs -f unsloth-amd`.

## Do not

- Pipe `install.sh` on the **host**. This runs `curl` in the container and `sh` on the machine you typed it on:

  ```bash
  # WRONG — host shell owns `| sh`
  docker compose exec unsloth-amd curl -fsSL https://unsloth.ai/install.sh | sh
  ```

  The host parser splits on `|` before Docker sees it: left side is `docker compose exec … curl` (script bytes come back to your terminal); right side is bare `sh` (executes those bytes as **root on `/`**, not in the volume).

  Either `exec … bash` first (procedure above), or quote the whole pipeline:

  ```bash
  docker compose exec unsloth-amd bash -lc 'curl -fsSL https://unsloth.ai/install.sh | sh'
  ```

- `rm -rf ~/.unsloth` inside the container. That path is a symlink to the shared install volume.
- Expect **`docker compose build`** to bump Unsloth. The image does not contain the package.
- Answer **Y** to start Studio from the installer (it would fight the existing Studio process).

## After install: torch pin

Upstream `install.sh` may pull a newer torch/ROCm combo that **SIGSEGVs on gfx1151**. Restarting `unsloth-amd` runs `docker-studio-pinned.sh`, which pins torch back to the verified-good wheels. See [Why runtime Unsloth install](Why-runtime-Unsloth-install.md).

## Wipe and reinstall instead

To throw away the shared venv and let the **entrypoint** run `install.sh` on next start (same as first boot), see the README section **Resetting / reinstalling Unsloth**. That is destructive for all three services’ Unsloth version; per-service Studio data stays on the `*-data` volumes.
