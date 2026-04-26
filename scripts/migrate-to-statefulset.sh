#!/usr/bin/env bash
# scripts/migrate-to-statefulset.sh — Migrate an overlay from Deployment to StatefulSet
set -euo pipefail

OVERLAY="${1:-}"
if [ -z "$OVERLAY" ]; then
  echo "Usage: $0 <overlay-name>"
  exit 1
fi

OVERLAY_DIR="overlays/$OVERLAY"
if [ ! -d "$OVERLAY_DIR" ]; then
  echo "Overlay not found: $OVERLAY"
  exit 1
fi

echo "Migrating $OVERLAY to StatefulSet..."

# Patch kustomization to replace deployment with statefulset
sed -i 's|../../base$|../../base/statefulset.yaml|' "$OVERLAY_DIR/kustomization.yaml"

echo "Done. Review $OVERLAY_DIR/kustomization.yaml and apply with:"
echo "  kubectl apply -k $OVERLAY_DIR"
