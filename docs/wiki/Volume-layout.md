# Volume layout

## Idea

Do **not** put install and save data in one Docker volume with nested overlays. Use **sibling** mounts. The entrypoint points `~/.unsloth` at the shared install so the official `curl | sh` updates the volume.

```text
/opt/unsloth-install   ← shared volume  unsloth-install     (Unsloth version)
/data/unsloth          ← per-service    unsloth-*-data      (save data)
/root/.cache           ← shared         unsloth-cache
/root/.local/share     ← shared         unsloth-share
~/.unsloth             ← symlink to /opt/unsloth-install (not a volume mount)
```

Defaults (override only if you change mount paths):

- `UNSLOTH_INSTALL_ROOT=/opt/unsloth-install`
- `UNSLOTH_DATA_ROOT=/data/unsloth`

## What goes where

| Location | Shared? | Contents |
|----------|---------|----------|
| `/opt/unsloth-install` | Yes (all services) | Studio venv, llama.cpp, helper venvs, `.docker-install-complete`, `.docker-torch-pin-complete` |
| `/data/unsloth` | No (per service) | `studio/auth`, `studio.db`, runs/exports/outputs, API key, last-model JSON |
| `/root/.cache` | Yes | HF / pip / uv downloads |
| `/root/.local/share` | Yes | uv-managed Python, launcher assets |

## Services

- **unsloth-amd** → `unsloth-amd-data`
- **unsloth-planner** → `unsloth-planner-data`
- **unsloth-builder** → `unsloth-builder-data`

All three mount the same `unsloth-install`, `unsloth-cache`, and `unsloth-share`.

## First boot order

1. `docker compose up -d` starts **unsloth-amd** first.
2. Planner/builder use `depends_on: condition: service_healthy` and wait until amd has:
   - `/opt/unsloth-install/studio/unsloth_studio/bin/unsloth`
   - `.docker-install-complete`
   - `.docker-torch-pin-complete`
3. Plain `depends_on` (without `service_healthy`) only waits for the container to *start*, not for install/pin to finish — avoid that race on a shared venv.

You can still start a single service alone (`docker compose up -d unsloth-planner`); Compose will pull in `unsloth-amd` as a dependency.

## Reset

- **Update** Unsloth in place (keep the volume): [Updating Unsloth](Update-Unsloth.md) — run `install.sh` inside `unsloth-amd`.
- Reinstall Unsloth (all services): remove/recreate `unsloth-install` (and clear the install marker on that volume).
- Wipe one service’s Studio state only: remove that service’s `*-data` volume.
- Cache only: `unsloth-cache` / `unsloth-share`.

## Why not nest mounts under `~/.unsloth`?

Mounting `home:/root/.unsloth` and then `install:/root/.unsloth/studio/unsloth_studio` **shadows** the subdirectory with an empty volume and forces awkward seeding. Sibling paths plus a **symlink** (`~/.unsloth` → `/opt/unsloth-install`) avoid that class of bug. Per-service dirs (`studio/auth`, `studio.db`, API keys) are further symlinked from the install tree to `/data/unsloth`.

See also: [Why runtime Unsloth install](Why-runtime-Unsloth-install.md).
