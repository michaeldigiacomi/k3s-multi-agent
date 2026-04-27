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
  find "$ROOT_DIR/overlays/" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sed 's/^/  /'
  exit 1
fi

OVERLAY="$1"
OVERLAY_DIR="$ROOT_DIR/overlays/$OVERLAY"

if [ ! -d "$OVERLAY_DIR" ]; then
  echo "Error: Overlay '$OVERLAY' not found at $OVERLAY_DIR"
  echo "Available overlays:"
  find "$ROOT_DIR/overlays/" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sed 's/^/  /'
  exit 1
fi

# Extract namespace from the kustomization
NAMESPACE=$(grep '^namespace:' "$OVERLAY_DIR/kustomization.yaml" | awk '{print $2}')
if [ -z "$NAMESPACE" ]; then
  echo "Error: No namespace found in $OVERLAY_DIR/kustomization.yaml"
  exit 1
fi

echo "🚀 Spinning up Hermes overlay: $OVERLAY (namespace: $NAMESPACE)"

# Apply the kustomization
kubectl apply -k "$OVERLAY_DIR"

# Reuse existing API_SERVER_KEY or generate a new one
if kubectl get secret hermes-secrets -n "$NAMESPACE" &>/dev/null; then
  EXISTING_KEY=$(kubectl get secret hermes-secrets -n "$NAMESPACE" -o jsonpath='{.data.API_SERVER_KEY}' | base64 -d)
  if [ -n "$EXISTING_KEY" ]; then
    echo "🔑 Reusing existing API_SERVER_KEY from namespace $NAMESPACE"
    API_SERVER_KEY="$EXISTING_KEY"
  else
    API_SERVER_KEY=$(openssl rand -hex 32)
    echo "🔑 Generated new API_SERVER_KEY"
  fi
else
  API_SERVER_KEY=$(openssl rand -hex 32)
  echo "🔑 Generated new API_SERVER_KEY"
fi

# Build a merged env file and apply the secret idempotently
TMP_ENV=$(mktemp)
echo "API_SERVER_KEY=$API_SERVER_KEY" > "$TMP_ENV"

if [ -f "$OVERLAY_DIR/secrets.env" ]; then
  echo "📄 Loading provider keys from $OVERLAY_DIR/secrets.env"
  cat "$OVERLAY_DIR/secrets.env" >> "$TMP_ENV"
else
  echo ""
  echo "⚠️  No secrets.env found at $OVERLAY_DIR/secrets.env"
  echo "   Create it from the example:"
  echo "   cp $OVERLAY_DIR/secrets.env.example $OVERLAY_DIR/secrets.env"
  echo "   # Edit $OVERLAY_DIR/secrets.env with your actual keys"
fi

kubectl create secret generic hermes-secrets \
  --from-env-file="$TMP_ENV" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

rm -f "$TMP_ENV"

# Restart to pick up new secret/config
if kubectl get statefulset hermes -n "$NAMESPACE" &>/dev/null; then
  WORKLOAD_KIND="statefulset"
else
  WORKLOAD_KIND="deployment"
fi

echo "🔄 Restarting $WORKLOAD_KIND/hermes..."
kubectl rollout restart "$WORKLOAD_KIND/hermes" -n "$NAMESPACE"

# Wait for rollout
echo "⏳ Waiting for rollout..."
kubectl rollout status "$WORKLOAD_KIND/hermes" -n "$NAMESPACE" --timeout=3m

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
