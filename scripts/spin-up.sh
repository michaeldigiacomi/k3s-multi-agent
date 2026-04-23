#!/usr/bin/env bash
# spin-up.sh — Deploy a Hermes agent overlay
# Usage: ./scripts/spin-up.sh <overlay-name>
# Example: ./scripts/spin-up.sh openai

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <overlay-name>"
  echo ""
  echo "Available overlays:"
  ls -1 "$ROOT_DIR/overlays/" 2>/dev/null | sed 's/^/  /'
  exit 1
fi

OVERLAY="$1"
OVERLAY_DIR="$ROOT_DIR/overlays/$OVERLAY"

if [ ! -d "$OVERLAY_DIR" ]; then
  echo "Error: Overlay '$OVERLAY' not found at $OVERLAY_DIR"
  echo "Available overlays:"
  ls -1 "$ROOT_DIR/overlays/" 2>/dev/null | sed 's/^/  /'
  exit 1
fi

# Extract namespace from the kustomization
NAMESPACE=$(grep 'namespace:' "$OVERLAY_DIR/kustomization.yaml" | awk '{print $2}')
if [ -z "$NAMESPACE" ]; then
  echo "Error: No namespace found in $OVERLAY_DIR/kustomization.yaml"
  exit 1
fi

echo "🚀 Spinning up Hermes overlay: $OVERLAY (namespace: $NAMESPACE)"

# Apply the kustomization
kubectl apply -k "$OVERLAY_DIR"

# Check if secret exists
if ! kubectl get secret hermes-secrets -n "$NAMESPACE" &>/dev/null; then
  echo ""
  echo "⚠️  No hermes-secrets found in namespace $NAMESPACE"
  echo "   Create it with:"
  echo "   cp $OVERLAY_DIR/secrets.env.example $OVERLAY_DIR/secrets.env"
  echo "   # Edit $OVERLAY_DIR/secrets.env with your API keys"
  echo "   kubectl create secret generic hermes-secrets --from-env-file=$OVERLAY_DIR/secrets.env -n $NAMESPACE"
  echo "   kubectl rollout restart deployment/hermes -n $NAMESPACE"
fi

echo ""
echo "✅ Overlay '$OVERLAY' deployed to namespace '$NAMESPACE'"
echo ""
echo "Port-forward to test:"
echo "  kubectl port-forward svc/hermes 8643:8642 -n $NAMESPACE"
echo ""
echo "Check status:"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "Tear down when done:"
echo "  ./scripts/tear-down.sh $OVERLAY"