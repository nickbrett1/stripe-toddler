#!/usr/bin/env sh
# goose-env-check.sh — Pre-flight diagnostic for running `goose` outside `goose-dev`.
#
# WHY THIS EXISTS
# ---------------
# The `goose-dev` zsh function (in ~/.zshrc) wraps goose in:
#     doppler run --project common --config dev -- doppler run --project goose --config prd -- goose "$@"
# which injects the env vars goose itself (LLM provider) and its MCP servers need.
# Running the bare `goose` binary skips that, so things fail with confusing errors:
#   - goose's litellm provider has no API key / endpoint  -> session can't start
#   - fintechnick MCP sends "Authorization: Bearer " (empty) -> cryptic 401
# This script makes it obvious WHICH var is missing and HOW to fix it.
#
# USAGE
# -----
#   scripts/goose-env-check.sh              # report + exit 0 / 1 / 2
#   scripts/goose-env-check.sh --strict     # treat optional (MCP) misses as fatal (exit 1)
#   GOOSE_ENV_CHECK_DISABLE=1 goose ...     # bypass (escape hatch for the goose wrapper)
#
# EXIT CODES
# ----------
#   0 = everything required is present (or only optional MCP tokens missing, non-strict)
#   1 = CRITICAL vars missing — goose cannot run at all (LLM provider)
#   2 = only OPTIONAL (MCP token) vars missing — goose runs, some extensions won't
#
# All diagnostics go to stderr so stdout stays clean for callers.

set -u

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

# Fast path: we are already inside `doppler run` (i.e. launched via goose-dev),
# so all secrets are guaranteed present. Skip probing entirely.
if [ -n "${DOPPLER_PROJECT:-}" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Collect missing vars
# ---------------------------------------------------------------------------
CRIT_MISSING=""
OPT_MISSING=""

# --- CRITICAL: goose's own LLM provider (litellm -> nas:4000) ----------------
if [ -z "${LITELLM_API_KEY:-}" ] && [ -z "${GOOSE_PROVIDER__API_KEY:-}" ]; then
  CRIT_MISSING="$CRIT_MISSING  - LITELLM_API_KEY (or GOOSE_PROVIDER__API_KEY) -> goose's LLM provider (litellm) has no API key\n"
fi
if [ -z "${LITELLM_HOST:-}" ]; then
  CRIT_MISSING="$CRIT_MISSING  - LITELLM_HOST -> litellm endpoint unknown; defaults to the public API and fails auth\n"
fi

# --- OPTIONAL: MCP servers that read tokens from the environment -------------
if [ -z "${FINTECHNICK_MCP:-}" ]; then
  OPT_MISSING="$OPT_MISSING  - FINTECHNICK_MCP -> disables the fintechnick MCP (finance/credit-card tools)\n"
fi
if [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
  OPT_MISSING="$OPT_MISSING  - GITHUB_TOKEN (or GITHUB_PERSONAL_ACCESS_TOKEN) -> disables the github MCP\n"
fi

# --- OPTIONAL: MCP servers that pull their tokens via `doppler run` ----------
# (sonarqube, circleci, github, doppler). Under plain `goose` these still work as
# long as the doppler CLI is authenticated and can reach common/dev. Probe once.
DOPPLER_OK=0
if command -v doppler >/dev/null 2>&1; then
  if doppler secrets get SONAR_TOKEN --project common --config dev --plain >/dev/null 2>&1; then
    DOPPLER_OK=1
  fi
fi
if [ "$DOPPLER_OK" -eq 0 ]; then
  OPT_MISSING="$OPT_MISSING  - doppler CLI secrets (common/dev) -> disables sonarqube, circleci, github + doppler MCP servers\n"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
banner() { echo "--------------------------------------------------------------------" >&2; }

if [ -z "$CRIT_MISSING" ] && [ -z "$OPT_MISSING" ]; then
  # Everything present (typical: launched via goose-dev). Stay silent for wrappers.
  exit 0
fi

echo "" >&2
banner
echo "goose is running WITHOUT the secrets that 'goose-dev' would inject." >&2
banner
if [ -n "$CRIT_MISSING" ]; then
  echo "" >&2
  echo "CRITICAL - goose cannot start a session until these are set:" >&2
  printf "$CRIT_MISSING" >&2
fi
if [ -n "$OPT_MISSING" ]; then
  echo "" >&2
  echo "OPTIONAL - goose will run, but these extensions will be unavailable:" >&2
  printf "$OPT_MISSING" >&2
fi
echo "" >&2
echo "Fix (recommended): start goose via the wrapper that injects Doppler secrets:" >&2
echo "    goose-dev" >&2
echo "" >&2
echo "Fix (manual): export the vars, e.g." >&2
echo "    export LITELLM_API_KEY=\$(doppler secrets get LITELLM_API_KEY --project goose --config prd --plain)" >&2
echo "    export FINTECHNICK_MCP=\$(doppler secrets get FINTECHNICK_MCP --project common --config dev --plain)" >&2
echo "" >&2
echo "To bypass this check entirely: GOOSE_ENV_CHECK_DISABLE=1 goose" >&2
echo "" >&2
banner
echo "" >&2

if [ -n "$CRIT_MISSING" ]; then
  exit 1
fi
if [ "$STRICT" -eq 1 ] && [ -n "$OPT_MISSING" ]; then
  exit 1
fi
exit 2
