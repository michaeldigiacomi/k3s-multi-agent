#!/usr/bin/env bash
# tear-down.sh — Remove a Hermes agent overlay (deletes namespace and all resources)
# Usage: ./scripts/tear-down.sh <overlay-name>
# Example: ./scripts/tear-down.sh openai

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <overlay-name>"
  exit 1
fi

OVERLAY="$1"
OVERLAY_DIR="$ROOT_DIR/overlays/$OVERLAY"

if [ ! -d "$OVERLAY_DIR" ]; then
  echo "Error: Overlay '$OVERLAY' not found at $OVERLAY_DIR"
  exit 1
fi

NAMESPACE=$(grep 'namespace:' "$OVERLAY_DIR/kustomization.yaml" | awk '{print $2}')
if [ -z "$NAMESPACE" ]; then
  echo "Error: No namespace found in $OVERLAY_DIR/kustomization.yaml"
  exit 1
fi

echo "🗑️  Tearing down Hermes overlay: $OVERLAY (namespace: $NAMESPACE)"
echo "   This will delete the namespace, PVC, and all resources."

# Trigger a backup before deletion
if command -v velero &>/dev/null; then
  echo "📦 Triggering pre-delete Velero backup for $NAMESPACE..."
  velero backup create "${NAMESPACE}-pre-delete-$(date +%s)" \
    --include-namespaces "$NAMESPACE" \
    --wait || true
fi

read -p "Are you sure? [y/N] " -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

kubectl delete namespace "$NAMESPACE" --wait=true

echo "✅ Overlay '$OVERLAY' (namespace '$NAMESPACE') deleted"