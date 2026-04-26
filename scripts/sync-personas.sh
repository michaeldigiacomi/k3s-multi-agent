#!/usr/bin/env bash
# sync-personas.sh — Sync persona files into overlay SOUL.md files
# Usage: ./scripts/sync-personas.sh [--commit] [--check]
#   --commit   Automatically commit synced files if they changed
#   --check    Exit with error if any files would be synced (CI lint mode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OVERLAY_MAP="$ROOT_DIR/overlay-map.yaml"

COMMIT=false
CHECK=false

for arg in "$@"; do
  case "$arg" in
    --commit) COMMIT=true ;;
    --check) CHECK=true ;;
  esac
done

if [ ! -f "$OVERLAY_MAP" ]; then
  echo "Error: overlay-map.yaml not found at $OVERLAY_MAP"
  exit 1
fi

SYNCED=()
CHANGED=()

echo "Syncing personas to overlays..."
while IFS=':' read -r overlay persona; do
  overlay=$(echo "$overlay" | xargs)
  persona=$(echo "$persona" | xargs)
  [ -z "$overlay" ] && continue
  [ -z "$persona" ] && continue
  [[ "$overlay" == \#* ]] && continue

  src="$ROOT_DIR/personas/$persona"
  dst="$ROOT_DIR/overlays/$overlay/SOUL.md"

  if [ ! -f "$src" ]; then
    echo "  WARNING: persona not found: $src"
    continue
  fi
  if [ ! -d "$ROOT_DIR/overlays/$overlay" ]; then
    echo "  WARNING: overlay not found: $ROOT_DIR/overlays/$overlay"
    continue
  fi

  if [ ! -f "$dst" ] || ! diff -q "$src" "$dst" > /dev/null 2>&1; then
    cp "$src" "$dst"
    echo "  $src -> $dst"
    SYNCED+=("$overlay")
    if [ -n "$(git -C "$ROOT_DIR" diff --name-only "$dst" 2>/dev/null || true)" ]; then
      CHANGED+=("$overlay")
    fi
  fi
done < "$OVERLAY_MAP"

if [ ${#SYNCED[@]} -eq 0 ]; then
  echo "No changes to sync."
  exit 0
fi

if [ "$CHECK" = true ]; then
  echo "Error: ${#SYNCED[@]} overlay(s) out of sync: ${SYNCED[*]}"
  exit 1
fi

if [ "$COMMIT" = true ]; then
  if git -C "$ROOT_DIR" diff --quiet overlays/*/SOUL.md 2>/dev/null; then
    echo "No synced persona changes to commit."
  else
    git -C "$ROOT_DIR" config user.name "github-actions[bot]"
    git -C "$ROOT_DIR" config user.email "github-actions[bot]@users.noreply.github.com"
    git -C "$ROOT_DIR" add overlays/*/SOUL.md
    git -C "$ROOT_DIR" commit -m "chore: sync persona files to overlays [skip ci]"
    git -C "$ROOT_DIR" push
    echo "Committed synced persona files."
  fi
fi
