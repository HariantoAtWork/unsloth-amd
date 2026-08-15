# Updating Unsloth

Unsloth is **not** in the Docker image and is **not** updated from the host checkout. `docker compose build` only rebuilds Ubuntu/ROCm/scripts. The package lives on the shared `unsloth-install` volume inside the containers.

Update it **inside the `unsloth-amd` container** (that service has the GPU devices `install.sh` needs). Planner and builder reuse the same volume, so they pick up the new version after restart.

## Procedure

On the host, from this directory, stop the other Studios so they are not using the venv mid-upgrade, then open a shell in `unsloth-amd`:

```bash
docker compose stop unsloth-planner unsloth-builder
docker compose exec unsloth-amd bash
```

Inside the container, point `~/.unsloth` at the shared install (the running layout is a symlink tree; `install.sh` must write into `/opt/unsloth-install`), then run the official installer:

```bash
export PATH="/opt/rocm/bin:/root/.local/bin:${PATH}"

rm -rf /root/.unsloth
ln -sfn /opt/unsloth-install /root/.unsloth

curl -fsSL https://unsloth.ai/install.sh | sh
```

When asked **Start Unsloth Studio now?**, answer **n**. Studio is started by the container command, not by the installer.

Leave the container, then restart so the entrypoint rebuilds the symlink layout and re-applies the gfx1151 torch pin:

```bash
exit
docker compose restart unsloth-amd
docker compose start unsloth-planner unsloth-builder
```

Watch pin/startup with `docker compose logs -f unsloth-amd`.

## Do not

- Run `install.sh` on the **host** — that Python/ROCm stack is not the one Studio uses.
- Expect **`docker compose build`** or editing `docker-entrypoint.sh` to bump Unsloth. The entrypoint only runs `install.sh` when `/opt/unsloth-install/.docker-install-complete` is missing **and** `unsloth` is not already on the volume.
- Answer **Y** to start Studio from the installer (it would fight the existing Studio process).

## After install: torch pin

Upstream `install.sh` may pull a newer torch/ROCm combo that **SIGSEGVs on gfx1151**. Restarting `unsloth-amd` runs `docker-studio-pinned.sh`, which pins torch back to the verified-good wheels. See [Why runtime Unsloth install](Why-runtime-Unsloth-install.md).

## Wipe and reinstall instead

To throw away the shared venv and let the **entrypoint** run `install.sh` on next start (same as first boot), see the README section **Resetting / reinstalling Unsloth**. That is destructive for all three services’ Unsloth version; per-service Studio data stays on the `*-data` volumes.
