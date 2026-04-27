#!/usr/bin/env bash
# scripts/drift-check.sh — Compare live cluster state against git manifests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXIT_CODE=0

for overlay_dir in "$ROOT_DIR"/overlays/*/; do
  overlay=$(basename "$overlay_dir")
  [[ "$overlay" == .* ]] && continue  # skip .DS_Store etc.
  namespace=$(grep '^namespace:' "$overlay_dir/kustomization.yaml" | awk '{print $2}')

  echo "=== Checking drift for $overlay (namespace: $namespace) ==="

  # Generate git-side manifest
  kubectl kustomize "$overlay_dir" > "/tmp/git-$overlay.yaml"

  # Check each workload (Deployment or StatefulSet) in the overlay
  for kind in Deployment StatefulSet; do
    for name in $(yq ". | select(.kind == \"$kind\") | .metadata.name" "/tmp/git-$overlay.yaml" 2>/dev/null); do
      resource_lower=$(echo "$kind" | tr '[:upper:]' '[:lower:]')

      if ! kubectl get "$resource_lower" "$name" -n "$namespace" &>/dev/null; then
        echo "  MISSING: $kind $name not found in namespace $namespace"
        EXIT_CODE=1
        continue
      fi

      # Get live manifest, strip server-generated fields, and compare
      kubectl get "$resource_lower" "$name" -n "$namespace" -o yaml \
        | yq 'del(.metadata.annotations["deployment.kubernetes.io/revision"])' \
        | yq 'del(.metadata.creationTimestamp, .metadata.generation, .metadata.resourceVersion, .metadata.uid)' \
        | yq 'del(.status)' \
        > "/tmp/live-$name.yaml"

      # Extract the same resource from the git manifest
      yq "select(.kind == \"$kind\" and .metadata.name == \"$name\")" "/tmp/git-$overlay.yaml" \
        > "/tmp/git-$name.yaml"

      if ! diff -u "/tmp/git-$name.yaml" "/tmp/live-$name.yaml" > "/tmp/diff-$name.txt" 2>/dev/null; then
        echo "  DRIFT: $kind $name differs from git"
        echo "  Diff:"
        head -30 "/tmp/diff-$name.txt" | sed 's/^/    /'
        EXIT_CODE=1
      else
        echo "  OK: $kind $name matches git"
      fi
    done
  done
done

if [ $EXIT_CODE -eq 0 ]; then
  echo "No drift detected."
else
  echo "Drift detected! Run 'kubectl apply -k overlays/<name>' to reconcile."
  exit 1
fi