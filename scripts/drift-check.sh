#!/usr/bin/env bash
# scripts/drift-check.sh — Compare live cluster state against git manifests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXIT_CODE=0

for overlay_dir in "$ROOT_DIR"/overlays/*/; do
  overlay=$(basename "$overlay_dir")
  namespace=$(grep '^namespace:' "$overlay_dir/kustomization.yaml" | awk '{print $2}')

  echo "=== Checking drift for $overlay (namespace: $namespace) ==="

  # Generate git-side manifest
  kubectl kustomize "$overlay_dir" > "/tmp/git-$overlay.yaml"

  # Check each deployment in the overlay
  for deployment in $(grep -E "^kind: Deployment" "/tmp/git-$overlay.yaml" -B1 | grep "name:" | awk '{print $2}'); do
    if ! kubectl get deployment "$deployment" -n "$namespace" &>/dev/null; then
      echo "  MISSING: Deployment $deployment not found in namespace $namespace"
      EXIT_CODE=1
      continue
    fi

    # Get live manifest, strip server-generated fields, and compare
    kubectl get deployment "$deployment" -n "$namespace" -o yaml \
      | yq 'del(.metadata.annotations["deployment.kubernetes.io/revision"])' \
      | yq 'del(.metadata.creationTimestamp, .metadata.generation, .metadata.resourceVersion, .metadata.uid)' \
      | yq 'del(.status)' \
      > "/tmp/live-$deployment.yaml"

    # Extract the same deployment from the git manifest
    yq "select(.kind == \"Deployment\" and .metadata.name == \"$deployment\")" "/tmp/git-$overlay.yaml" \
      > "/tmp/git-$deployment.yaml"

    if ! diff -u "/tmp/git-$deployment.yaml" "/tmp/live-$deployment.yaml" > "/tmp/diff-$deployment.txt" 2>/dev/null; then
      echo "  DRIFT: Deployment $deployment differs from git"
      echo "  Diff:"
      head -30 "/tmp/diff-$deployment.txt" | sed 's/^/    /'
      EXIT_CODE=1
    else
      echo "  OK: Deployment $deployment matches git"
    fi
  done
done

if [ $EXIT_CODE -eq 0 ]; then
  echo "No drift detected."
else
  echo "Drift detected! Run 'kubectl apply -k overlays/<name>' to reconcile."
  exit 1
fi
