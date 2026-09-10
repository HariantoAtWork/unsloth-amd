#!/usr/bin/env bash
# Apply the same --no-launch edits as docker-entrypoint.sh's _patch_install_sh:
#
#   1. After _VERBOSE=false → add _NO_LAUNCH_FLAG=false
#   2. After --verbose|-v) _VERBOSE=true ;; → add --no-launch) _NO_LAUNCH_FLAG=true ;;
#   3. Before “# In interactive terminals…” → insert:
#        if [ "${_NO_LAUNCH_FLAG:-false}" = true ]; then
#            exit 0
#        fi
#
# Usage:
#   ./patch.sh [--diff] <installer.sh> [output.sh]
#
# Default output: <name>.patched.sh (e.g. installer.patched.sh). Original file is never modified.
# With --diff: prints unified diff after writing.

set -euo pipefail

DIFF=false
while [[ "${1:-}" == -* ]]; do
    case "$1" in
        --diff) DIFF=true ; shift ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

INPUT="${1:?Usage: $0 [--diff] <installer.sh> [output.sh]}"
OUTPUT="${2:-${INPUT%.sh}.patched.sh}"

if [[ ! -f "${INPUT}" ]]; then
    echo "Not found: ${INPUT}" >&2
    exit 1
fi

cp "${INPUT}" "${OUTPUT}"

sed -i '/^_VERBOSE=false$/a _NO_LAUNCH_FLAG=false' "${OUTPUT}"
sed -i '/--verbose|-v) _VERBOSE=true ;;/a\
        --no-launch) _NO_LAUNCH_FLAG=true ;;' "${OUTPUT}"

awk '
/^# In interactive terminals, ask the user before starting Studio\.$/ {
    print "if [ \"${_NO_LAUNCH_FLAG:-false}\" = true ]; then"
    print "    exit 0"
    print "fi"
    print ""
}
{ print }
' "${OUTPUT}" > "${OUTPUT}.tmp"
mv "${OUTPUT}.tmp" "${OUTPUT}"

echo "Patched → ${OUTPUT}"

if [[ "${DIFF}" == true ]]; then
    echo ""
    echo "=== diff -u ${INPUT} ${OUTPUT} ==="
    diff -u "${INPUT}" "${OUTPUT}" || true
fi
