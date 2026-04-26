#!/usr/bin/env bash
# scripts/validate-persona.sh — Validate SOUL.md files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXIT_CODE=0

for persona in "$ROOT_DIR"/personas/*.md; do
  [ -e "$persona" ] || continue
  FILENAME=$(basename "$persona")
  echo "Validating $FILENAME..."

  # Check minimum length
  LINES=$(wc -l < "$persona")
  if [ "$LINES" -lt 10 ]; then
    echo "  ERROR: $FILENAME is too short ($LINES lines, minimum 10)"
    EXIT_CODE=1
  fi

  # Check for required sections
  if ! grep -qE "^# " "$persona"; then
    echo "  ERROR: $FILENAME missing top-level heading (# Title)"
    EXIT_CODE=1
  fi

  if ! grep -qiE "(persona|identity|role|expertise)" "$persona"; then
    echo "  ERROR: $FILENAME missing persona identity indicators"
    EXIT_CODE=1
  fi

  if ! grep -qiE "(principle|value|guideline|behavior)" "$persona"; then
    echo "  WARNING: $FILENAME missing behavioral principles section"
  fi
done

if [ $EXIT_CODE -eq 0 ]; then
  echo "All personas valid."
else
  echo "Persona validation failed."
  exit 1
fi
