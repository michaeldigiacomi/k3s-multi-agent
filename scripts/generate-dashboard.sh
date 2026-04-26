#!/usr/bin/env bash
# scripts/generate-dashboard.sh — Validate and pretty-print the dashboard JSON
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD="$ROOT_DIR/observability/grafana-dashboard.json"

if [ ! -f "$DASHBOARD" ]; then
  echo "Error: Dashboard not found at $DASHBOARD"
  exit 1
fi

# Validate JSON
jq empty "$DASHBOARD"
echo "Dashboard JSON is valid."
echo "Panels: $(jq '.dashboard.panels | length' "$DASHBOARD")"
