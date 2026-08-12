# Three Unsloth Studios on one AMD GPU (and why the install is not in the Dockerfile)

*Notes from wiring Unsloth Studio into Docker on a Radeon 8060S (gfx1151), then deciding Ollama and Docker Model Runner could wait.*

---

I wanted Unsloth Studio on AMD ROCm, in Docker, without turning the machine into a single-purpose appliance. The goal sounded simple: one image, GPU passthrough, Studio on a port. The interesting part was everything that is *not* in the Dockerfile.

## The image is not the model runtime

A fresh `docker build` for this stack installs Ubuntu, the ROCm apt packages, Bun, and a handful of scripts. It does **not** run `https://unsloth.ai/install.sh`.

That is deliberate. The official installer wants to see a real GPU — `/dev/kfd`, `/dev/dri`, `rocminfo` on `PATH`. A normal image build does not get those device nodes. Install at build time and you risk a CPU PyTorch wheel, a half-broken “success”, or a multi‑gigabyte layer that is wrong for the card you actually own.

So the container entrypoint does the Unsloth install on **first start**, when Compose has already passed the GPU in via `devices:`. After that, a small startup script pins torch to the stack that actually works on gfx1151. Upstream’s newest ROCm torch was happy to SIGSEGV on this Strix Halo / 8060S class GPU; the highest verified-good combo here has been torch `2.10.0+rocm7.12.0` from AMD’s gfx1151 wheel index. The image tag carries that story: `…-torch2.10.0-rocm7.12.0`.

If you take one idea from this post: **bake the host environment; install the ML stack where the GPU is visible.**

## `image:` is not the same as “Unsloth is installed”

Compose has three services — main Studio, a planner, a builder — all pointing at the same `harianto/unsloth-amd:…` image. Sharing an image shares ROCm userspace and scripts. It does **not** share the Unsloth venv.

Unsloth lands under a volume at `/opt/unsloth-install`. All three containers mount that volume. First boot runs `install.sh` once; the others see a usable install and skip the long path. Studio *state* — auth database, API keys, last loaded model, runs and exports — lives on **per-service** volumes at `/data/unsloth`. Same Unsloth version, separate personalities.

That split took a few wrong turns. Nested mounts under `~/.unsloth` (home volume plus overlays for `unsloth_studio` and `llama.cpp`) work until an empty named volume shadows the install you thought you kept. The layout that stuck is dull and solid:

| Path | Volume | Role |
|------|--------|------|
| `/opt/unsloth-install` | shared | venv, llama.cpp, install markers |
| `/data/unsloth` | per service | auth, `studio.db`, runs, keys |
| `/root/.cache` | shared | Hugging Face / pip / uv downloads |
| `~/.unsloth` | not a volume | symlink tree rebuilt every start |

The entrypoint rebuilds `~/.unsloth` as junctions into install + data. Unsloth still believes it lives in the usual home layout; Docker never overlays a directory on top of itself.

## Studio is Python, not a Node app

Easy mistake: the UI looks like a modern JS product, so you assume `node` or `bun` is what “opens” Unsloth. In this setup the CLI is a Python entrypoint; the backend serves a prebuilt frontend. Bun is in the image for Unsloth’s own tooling (agents / extensions), not because Studio is a Bun server. Knowing that saves you from optimising the wrong runtime.

## GPU passthrough: `devices:` was enough

There is a whole folklore branch about bind-mounting `/dev/dri` because it is a directory and `devices:` might not expose the full DRM tree. On this host, Compose `devices: [/dev/kfd, /dev/dri]` was enough for `rocminfo` and the installer. Extra `-v /dev/dri:/dev/dri` mounts would have been ceremony. Prefer the simple path until the GPU is invisible; then escalate.

## Snappy vs heavy: Unsloth, Ollama, Model Runner

After living with a few local-AI Docker habits side by side, the trade-offs got blunt.

**Unsloth Studio** felt snappier for interactive work on this ROCm stack, and the three-container layout means three Studio contexts on one GPU without three full installs. VRAM is still one pie — you do not magically triple memory — but process and config isolation is real.

**Ollama** remains excellent as a model pantry. Its volume on this machine had grown to on the order of **200 GB+**. That is not a criticism; it is what “pull everything interesting” looks like.

**Docker Model Runner** was fun to try and expensive to keep. Uninstalling the runner with models and images reclaimed on the order of **170 GB**, and `/home` free space jumped by a couple of hundred gigabytes overnight. The CLI plugin can linger; the runner and the model store do not have to.

Anonymous Docker volumes with 64‑character hex names are mostly leftover noise from unnamed mounts — often only a few gigabytes in total. They look scary in `docker volume ls`; they are rarely the villain. Named volumes with honest names are where the disk went.

## What I would repeat

1. **Do not install Unsloth in the Dockerfile** unless you have a GPU-aware build and a pinned torch story you trust.
2. **Share one install volume; isolate data volumes** when you want several Studios or roles.
3. **Name your volumes.** Future you will thank present you when pruning.
4. **Treat model stores as first-class disk citizens.** Ollama and Model Runner will outgrow the OS partition jokes if you let them.
5. **Document the weird decisions** — runtime install, torch pin, sibling mounts — in a small in-repo wiki. Clever setups rot without a sentence that says *why*.

## Closing

The clever bit was not “AI in Docker”. It was admitting that the Dockerfile is a ROCm boot environment, the entrypoint is where Unsloth meets the GPU, and volumes are how you share a version without sharing passwords and last-model JSON across three containers.

Unsloth stays. Model Runner went to the bit-bucket. Ollama can keep the heavy models if I still want a pantry. Three Studios on one AMD GPU is enough mischief for one machine.

---

*Stack sketch: Ubuntu 24.04 image, ROCm apt `7.2.x`, torch `2.10.0+rocm7.12.0` for gfx1151, Unsloth via official `install.sh` at container start, Compose services `unsloth-amd` / `unsloth-planner` / `unsloth-builder`.*
