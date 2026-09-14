#!/usr/bin/env bash
# patches/generate-curl-sources.sh
#
# Copies the Phase 3 libcurl replacement sources from patches/curl/
# into amaya/ (preserving the originals as *.libwww).
#
# Called automatically by apply-patches.sh when patches/curl/ exists.
# Run manually if you want to install them independently.
#
# Usage: bash patches/generate-curl-sources.sh [--force]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CURL_SRC="$SCRIPT_DIR/curl"
AMAYA="$ROOT/amaya"

FORCE=${1:-}

log() { echo "[curl] $*"; }

for f in query.c answer.c AHTBridge.c AHTInit.c AHTMemConv.c AHTFWrite.c AHTEvntrg.c; do
  ORIG="$AMAYA/$f"
  SAVED="${ORIG%.c}.libwww"
  REPLACEMENT="$CURL_SRC/$f"

  [ -f "$REPLACEMENT" ] || { log "SKIP $f (no replacement in patches/curl/)"; continue; }

  # Preserve original
  if [ -f "$ORIG" ] && [ ! -f "$SAVED" ]; then
    log "Preserving $f → ${f%.c}.libwww"
    cp "$ORIG" "$SAVED"
  fi

  # Install replacement
  if [ ! -f "$ORIG" ] || [ -n "$FORCE" ] || [ "$REPLACEMENT" -nt "$ORIG" ]; then
    log "Installing libcurl replacement: $f"
    cp "$REPLACEMENT" "$ORIG"
  else
    log "Up to date: $f"
  fi
done

# Copy the shared header into amaya/ so the replacement files can include it
cp "$CURL_SRC/AHTReqContext_curl.h" "$AMAYA/"

log "Done. Phase 3 libcurl sources installed in amaya/."
log "To revert: for f in amaya/*.libwww; do cp \"\$f\" \"\${f%.libwww}.c\"; done"

# Replace libwww.h with the curl-compatible stub
if [ -f "$CURL_SRC/libwww.h" ]; then
  log "Installing libwww.h replacement"
  cp "$CURL_SRC/libwww.h" "$AMAYA/libwww.h"
fi
