# Unsloth AMD Docker — wiki

In-repo notes for design decisions that are easy to forget. Start here:

| Page | What |
|------|------|
| [Why runtime Unsloth install](Why-runtime-Unsloth-install.md) | Why `install.sh` runs in the entrypoint, not the Dockerfile |
| [Volume layout](Volume-layout.md) | Shared install vs per-service data; what `image:` does and does not include |
| [Blog: three Studios on one AMD GPU](../blog/2026-08-12-three-unsloth-studios-on-one-amd-gpu.md) | Narrative write-up of the setup choices |

Operational how-to (compose up, ports, troubleshooting) stays in the root [README](../README.md).
