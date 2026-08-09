#!/usr/bin/env sh
# goose wrapper — pre-flight env check, then exec the real binary (goose-bin).
#
# The real goose binary is installed at ~/.local/bin/goose-bin (see Dockerfile +
# post-create-setup.sh). This wrapper sits at ~/.local/bin/goose so that launching
# `goose` without `goose-dev` (which injects Doppler secrets) explains exactly what
# is missing instead of failing with cryptic provider/MCP errors.
#
# Managed by .devcontainer/post-create-setup.sh — do not edit manually.

BIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REAL_BIN="$BIN_DIR/goose-bin"

# Locate the env check script (repo checkout preferred, fallback next to wrapper)
CHECK_SCRIPT="${GOOSE_ENV_CHECK_SCRIPT:-/workspaces/stripe-toddler/scripts/goose-env-check.sh}"
[ -x "$CHECK_SCRIPT" ] || CHECK_SCRIPT="$BIN_DIR/goose-env-check.sh"

# Explicit diagnostic mode: goose --check-env
if [ "${1:-}" = "--check-env" ]; then
  if [ -x "$CHECK_SCRIPT" ]; then
    "$CHECK_SCRIPT" --strict
    rc=$?
  else
    echo "goose wrapper: env-check script not found ($CHECK_SCRIPT)" >&2
    rc=1
  fi
  exit "$rc"
fi

# Don't run the check for informational invocations
skip=0
for a in "$@"; do
  case "$a" in
    --version|-V|--help|-h|help|version) skip=1; break ;;
  esac
done

if [ "$skip" -eq 0 ] && [ -z "${GOOSE_ENV_CHECK_DISABLE:-}" ] && [ -x "$CHECK_SCRIPT" ]; then
  "$CHECK_SCRIPT"
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "Blocked: fix the CRITICAL missing variables above, or bypass with: GOOSE_ENV_CHECK_DISABLE=1 goose" >&2
    exit 1
  fi
  # rc 0 (all good) or 2 (only optional MCP tokens missing) -> continue
fi

exec "$REAL_BIN" "$@"
