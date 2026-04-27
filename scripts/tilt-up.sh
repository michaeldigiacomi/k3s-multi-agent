#!/usr/bin/env bash
# scripts/tilt-up.sh — Start Tilt for a given overlay
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OVERLAY="${1:-openai}"

if [ ! -d "$ROOT_DIR/overlays/$OVERLAY" ]; then
  echo "Error: overlay '$OVERLAY' not found"
  echo "Available:"
  find "$ROOT_DIR/overlays/" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
  exit 1
fi

cd "$ROOT_DIR"
tilt up -- --overlay="$OVERLAY"
