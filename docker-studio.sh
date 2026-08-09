#!/usr/bin/env bash
# Start Unsloth Studio. When ~/.unsloth/.docker-last-model.json exists, reload that
# model via `unsloth studio run`. A background watcher rewrites the JSON whenever
# the active model changes so the next container restart restores it.
set -euo pipefail

export PATH="/opt/rocm/bin:/root/.bun/bin:/root/.local/bin:${PATH}"

HOST="${UNSLOTH_STUDIO_HOST:-0.0.0.0}"
PORT="${UNSLOTH_STUDIO_PORT:-8888}"
AUTOLOAD="${UNSLOTH_AUTOLOAD_LAST_MODEL:-1}"
LAST_MODEL_FILE="${UNSLOTH_LAST_MODEL_FILE:-${HOME}/.unsloth/.docker-last-model.json}"
WATCH_INTERVAL="${UNSLOTH_LAST_MODEL_WATCH_SECONDS:-15}"
# Local loopback for health/status even when Studio binds 0.0.0.0.
API_BASE="http://127.0.0.1:${PORT}"

UNSLOTH=""
for _c in "${HOME}/.local/bin/unsloth" "${HOME}/.unsloth/studio/unsloth_studio/bin/unsloth"; do
    if [[ -x "${_c}" ]]; then
        UNSLOTH="${_c}"
        break
    fi
done

if [[ -z "${UNSLOTH}" ]]; then
    echo "ERROR: unsloth not found. Remove ~/.unsloth/.docker-install-complete or volumes and recreate the container." >&2
    exit 127
fi

STUDIO_PID=""
WATCHER_PID=""
LOG_FILE="$(mktemp -t unsloth-studio-XXXXXX.log)"

_cleanup() {
    local ec=$?
    if [[ -n "${WATCHER_PID}" ]] && kill -0 "${WATCHER_PID}" 2>/dev/null; then
        kill "${WATCHER_PID}" 2>/dev/null || true
        wait "${WATCHER_PID}" 2>/dev/null || true
    fi
    if [[ -n "${STUDIO_PID}" ]] && kill -0 "${STUDIO_PID}" 2>/dev/null; then
        kill "${STUDIO_PID}" 2>/dev/null || true
        wait "${STUDIO_PID}" 2>/dev/null || true
    fi
    rm -f "${LOG_FILE}"
    exit "${ec}"
}

_forward_signal() {
    local sig="$1"
    if [[ -n "${STUDIO_PID}" ]] && kill -0 "${STUDIO_PID}" 2>/dev/null; then
        kill "-${sig}" "${STUDIO_PID}" 2>/dev/null || true
    fi
}

trap _cleanup EXIT
trap '_forward_signal TERM' TERM
trap '_forward_signal INT' INT

_autoload_enabled() {
    case "${AUTOLOAD}" in
        0|false|FALSE|no|NO|off|OFF) return 1 ;;
        *) return 0 ;;
    esac
}

_read_last_model() {
    # Prints: model_path<TAB>gguf_variant<TAB>max_seq_length
    python3 - "${LAST_MODEL_FILE}" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
model = (data.get("model_path") or data.get("model_identifier") or "").strip()
if not model:
    sys.exit(1)
variant = data.get("gguf_variant") or ""
if variant is None:
    variant = ""
variant = str(variant).strip()
try:
    max_seq = int(data.get("max_seq_length") or 0)
except Exception:
    max_seq = 0
print(f"{model}\t{variant}\t{max_seq}")
PY
}

_write_last_model() {
    local model_path="$1"
    local gguf_variant="${2:-}"
    local max_seq_length="${3:-0}"
    mkdir -p "$(dirname "${LAST_MODEL_FILE}")"
    python3 - "${LAST_MODEL_FILE}" "${model_path}" "${gguf_variant}" "${max_seq_length}" <<'PY'
import json, sys
path, model, variant, max_seq = sys.argv[1:5]
payload = {
    "model_path": model,
    "gguf_variant": variant or None,
    "max_seq_length": int(max_seq or 0),
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
print(f"saved last model -> {path}: {payload}", flush=True)
PY
}

_wait_for_health() {
    local i
    for i in $(seq 1 180); do
        if curl -fsS "${API_BASE}/api/health" >/dev/null 2>&1 \
            || curl -fsS "${API_BASE}/health" >/dev/null 2>&1; then
            return 0
        fi
        if [[ -n "${STUDIO_PID}" ]] && ! kill -0 "${STUDIO_PID}" 2>/dev/null; then
            echo "==> Studio exited before becoming healthy" >&2
            return 1
        fi
        sleep 2
    done
    echo "==> Timed out waiting for Studio health at ${API_BASE}" >&2
    return 1
}

_bootstrap_password() {
    local f="${HOME}/.unsloth/studio/auth/.bootstrap_password"
    if [[ -n "${UNSLOTH_STUDIO_PASSWORD:-}" ]]; then
        printf '%s' "${UNSLOTH_STUDIO_PASSWORD}"
        return 0
    fi
    if [[ -r "${f}" ]]; then
        # File is "secret\n"; strip a single trailing newline only.
        python3 - "${f}" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text(encoding="utf-8").rstrip("\n"), end="")
PY
        return 0
    fi
    return 1
}

_studio_backend_dir() {
    local d
    for d in "${HOME}/.unsloth/studio/unsloth_studio"/lib/python*/site-packages/studio/backend; do
        if [[ -d "${d}" ]]; then
            printf '%s' "${d}"
            return 0
        fi
    done
    return 1
}

# Mint/reuse an internal Studio API key so /api/inference/status works even when
# the admin still has must_change_password (JWT login returns 403 for status).
_ensure_watcher_api_key() {
    if [[ -n "${UNSLOTH_API_KEY:-}" ]]; then
        printf '%s' "${UNSLOTH_API_KEY}"
        return 0
    fi

    local backend key_file py
    backend="$(_studio_backend_dir)" || return 1
    py="${HOME}/.unsloth/studio/unsloth_studio/bin/python"
    if [[ ! -x "${py}" ]]; then
        py="$(command -v python3)"
    fi
    key_file="${HOME}/.unsloth/.docker-watcher-api-key"
    mkdir -p "$(dirname "${key_file}")"

    (
        cd "${backend}"
        "${py}" - "${key_file}" <<'PY'
import sys
from pathlib import Path

key_file = Path(sys.argv[1])
from auth.storage import (
    DEFAULT_ADMIN_USERNAME,
    create_api_key,
    validate_api_key,
)

if key_file.is_file():
    raw = key_file.read_text(encoding="utf-8").strip()
    if raw and validate_api_key(raw):
        print(raw)
        raise SystemExit(0)

raw, _row = create_api_key(
    DEFAULT_ADMIN_USERNAME,
    name="docker-last-model-watcher",
    internal=True,
)
key_file.write_text(raw + "\n", encoding="utf-8")
key_file.chmod(0o600)
print(raw)
PY
    )
}

_login_token() {
    local password
    password="$(_bootstrap_password)" || return 1
    python3 - "${API_BASE}" "unsloth" "${password}" <<'PY'
import json, sys, urllib.error, urllib.request
base, user, password = sys.argv[1:4]
req = urllib.request.Request(
    f"{base}/api/auth/login",
    data=json.dumps({"username": user, "password": password}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.load(resp)
except Exception as exc:
    print(f"login failed: {exc}", file=sys.stderr)
    sys.exit(1)
# Password-change JWTs cannot call /api/inference/status (403).
if body.get("must_change_password"):
    sys.exit(1)
token = body.get("access_token") or ""
if not token:
    sys.exit(1)
print(token)
PY
}

_extract_api_key_from_log() {
    # Prefer a freshly printed Studio API key from studio run / startup banners.
    python3 - "${LOG_FILE}" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
# Common Unsloth key shapes: sk-... or sk-unsloth-...
keys = re.findall(r"\b(sk-(?:unsloth-)?[A-Za-z0-9_\-]{16,})\b", text)
if keys:
    print(keys[-1])
    sys.exit(0)
sys.exit(1)
PY
}

_extract_model_from_log() {
    python3 - "${LOG_FILE}" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
# Examples:
#   Model loaded: unsloth/Qwen3-1.7B-GGUF (Q4_K_M)
#   Reusing loaded model: unsloth/Qwen3-0.6B-GGUF:Q4_K_M
patterns = [
    re.compile(r"Model loaded:\s*([^\s(]+)(?:\s*\(([^)]+)\))?", re.I),
    re.compile(r"Reusing loaded model:\s*([^:\s]+)(?::(\S+))?", re.I),
]
model = variant = None
for pat in patterns:
    for m in pat.finditer(text):
        model = m.group(1).strip()
        variant = (m.group(2) or "").strip() or None
if not model:
    sys.exit(1)
print(f"{model}\t{variant or ''}")
PY
}

_poll_status_and_save() {
    local token="$1"
    python3 - "${API_BASE}" "${token}" "${LAST_MODEL_FILE}" <<'PY'
import json, sys, urllib.error, urllib.request
from pathlib import Path

base, token, path = sys.argv[1:4]
req = urllib.request.Request(
    f"{base}/api/inference/status",
    headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    method="GET",
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.load(resp)
except Exception as exc:
    print(f"status poll failed: {exc}", file=sys.stderr)
    sys.exit(2)

model = (
    data.get("model_identifier")
    or data.get("active_model")
    or ""
)
if isinstance(model, str):
    model = model.strip()
else:
    model = ""
if not model:
    loaded = data.get("loaded") or []
    if isinstance(loaded, list) and loaded:
        first = loaded[0]
        if isinstance(first, str):
            model = first.strip()
        elif isinstance(first, dict):
            model = str(
                first.get("model_identifier")
                or first.get("id")
                or first.get("name")
                or ""
            ).strip()
if not model:
    sys.exit(0)

variant = data.get("gguf_variant")
if variant is not None:
    variant = str(variant).strip() or None
# Allow model_identifier forms like org/repo:Q4_K_M
if not variant and ":" in model and not model.startswith("/"):
    model, variant = model.rsplit(":", 1)

payload = {
    "model_path": model,
    "gguf_variant": variant,
    "max_seq_length": int(data.get("context_length") or 0),
}

prev = None
p = Path(path)
if p.is_file():
    try:
        prev = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        prev = None

if prev and prev.get("model_path") == payload["model_path"] and (prev.get("gguf_variant") or None) == payload["gguf_variant"]:
    sys.exit(0)

p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(f"saved last model -> {path}: {payload}", flush=True)
PY
}

_watcher() {
    echo "==> Last-model watcher started (interval ${WATCH_INTERVAL}s)"
    if ! _wait_for_health; then
        return 0
    fi

    local token=""
    token="$(_ensure_watcher_api_key 2>/dev/null || true)"
    if [[ -z "${token}" ]]; then
        token="$(_login_token 2>/dev/null || true)"
    fi
    if [[ -z "${token}" ]]; then
        token="$(_extract_api_key_from_log 2>/dev/null || true)"
    fi
    if [[ -n "${token}" ]]; then
        echo "==> Watcher authenticated for /api/inference/status"
    else
        echo "==> Watcher has no API token yet; will use log parsing and retry key minting"
    fi

    local last_log_model=""
    while [[ -n "${STUDIO_PID}" ]] && kill -0 "${STUDIO_PID}" 2>/dev/null; do
        if [[ -z "${token}" ]]; then
            token="$(_ensure_watcher_api_key 2>/dev/null || true)"
            if [[ -z "${token}" ]]; then
                token="$(_login_token 2>/dev/null || true)"
            fi
            if [[ -z "${token}" ]]; then
                token="$(_extract_api_key_from_log 2>/dev/null || true)"
            fi
        fi

        if [[ -n "${token}" ]]; then
            if ! _poll_status_and_save "${token}"; then
                # Token may be rejected; force rediscovery next loop.
                token=""
            fi
        fi

        local parsed
        if parsed="$(_extract_model_from_log 2>/dev/null)"; then
            local model variant
            IFS=$'\t' read -r model variant <<<"${parsed}"
            if [[ -n "${model}" && "${parsed}" != "${last_log_model}" ]]; then
                last_log_model="${parsed}"
                _write_last_model "${model}" "${variant}" 0 || true
            fi
        fi

        sleep "${WATCH_INTERVAL}"
    done
}

_build_and_start_studio() {
    local args=()

    if _autoload_enabled && [[ -f "${LAST_MODEL_FILE}" ]]; then
        local row model variant max_seq
        if row="$(_read_last_model)"; then
            IFS=$'\t' read -r model variant max_seq <<<"${row}"
            echo "==> Autoloading last model: ${model}${variant:+ (${variant})}"
            # `studio run` has its own --host/--port (default 127.0.0.1). Parent
            # `studio --host` flags are ignored for this subcommand.
            # Do NOT pass --enable-tools here: with tools on, GGUF chat always
            # returns SSE (incl. non-OpenAI tool_status events) even for
            # stream=false, which breaks external OpenAI-compatible clients.
            args=(
                studio run
                --host "${HOST}"
                --port "${PORT}"
                --yes
                --model "${model}"
            )
            if [[ -n "${variant}" && "${variant}" != "None" ]]; then
                args+=(--gguf-variant "${variant}")
            fi
            if [[ -n "${max_seq}" && "${max_seq}" != "0" ]]; then
                args+=(--max-seq-length "${max_seq}")
            fi
        else
            echo "==> Ignoring invalid ${LAST_MODEL_FILE}; starting Studio without a model"
            args=(studio --host "${HOST}" --port "${PORT}")
        fi
    else
        if ! _autoload_enabled; then
            echo "==> Autoload disabled (UNSLOTH_AUTOLOAD_LAST_MODEL=${AUTOLOAD})"
        else
            echo "==> No last-model file at ${LAST_MODEL_FILE}; starting Studio without a model"
        fi
        args=(studio --host "${HOST}" --port "${PORT}")
    fi

    # Tee logs for the watcher (API key / Model loaded lines) while keeping console output.
    set +e
    "${UNSLOTH}" "${args[@]}" > >(tee -a "${LOG_FILE}") 2> >(tee -a "${LOG_FILE}" >&2) &
    STUDIO_PID=$!
    set -e
}

_build_and_start_studio
_watcher &
WATCHER_PID=$!

set +e
wait "${STUDIO_PID}"
ec=$?
set -e
STUDIO_PID=""
exit "${ec}"
