# Volume layout

## Idea

Do **not** put install and save data in one Docker volume with nested overlays. Use **sibling** mounts; the entrypoint rebuilds `~/.unsloth` as symlinks on every start.

```text
/opt/unsloth-install   ← shared volume  unsloth-install     (Unsloth version)
/data/unsloth          ← per-service    unsloth-*-data      (save data)
/root/.cache           ← shared         unsloth-cache
/root/.local/share     ← shared         unsloth-share
~/.unsloth             ← ephemeral symlink tree (not a volume)
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

1. Start one service that has GPU access (usually `unsloth-amd`).
2. Let entrypoint run `install.sh` into `unsloth-install`.
3. Start planner/builder — they should see the shared install and skip a full reinstall.

## Reset

- Reinstall Unsloth (all services): remove/recreate `unsloth-install` (and clear the install marker on that volume).
- Wipe one service’s Studio state only: remove that service’s `*-data` volume.
- Cache only: `unsloth-cache` / `unsloth-share`.

## Why not nest mounts under `~/.unsloth`?

Mounting `home:/root/.unsloth` and then `install:/root/.unsloth/studio/unsloth_studio` **shadows** the subdirectory with an empty volume and forces awkward seeding. Sibling paths avoid that class of bug.

See also: [Why runtime Unsloth install](Why-runtime-Unsloth-install.md).
