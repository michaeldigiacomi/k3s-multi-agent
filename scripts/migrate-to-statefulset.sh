#!/usr/bin/env bash
# scripts/migrate-to-statefulset.sh — Migrate an overlay from Deployment to StatefulSet
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OVERLAY="${1:-}"
if [ -z "$OVERLAY" ]; then
  echo "Usage: $0 <overlay-name>"
  echo ""
  echo "Available overlays:"
  find "$ROOT_DIR/overlays/" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed 's/^/  /'
  exit 1
fi

OVERLAY_DIR="$ROOT_DIR/overlays/$OVERLAY"
if [ ! -d "$OVERLAY_DIR" ]; then
  echo "Error: Overlay '$OVERLAY' not found at $OVERLAY_DIR"
  exit 1
fi

KUSTOMIZATION="$OVERLAY_DIR/kustomization.yaml"
if [ ! -f "$KUSTOMIZATION" ]; then
  echo "Error: No kustomization.yaml in $OVERLAY_DIR"
  exit 1
fi

# Verify the overlay currently uses the base (which includes deployment.yaml)
if ! grep -q '../../base' "$KUSTOMIZATION"; then
  echo "Error: Overlay does not reference ../../base — manual migration required."
  exit 1
fi

echo "Migrating $OVERLAY to StatefulSet..."
echo ""
echo "This will:"
echo "  1. Add statefulset.yaml to base/kustomization.yaml"
echo "  2. Add a patch to exclude deployment.yaml and pvc.yaml for this overlay"
echo "  3. Add a patch to update HPA scaleTargetRef to StatefulSet"
echo ""

# Step 1: Add statefulset.yaml to base kustomization if not already present
BASE_KUSTOMIZATION="$ROOT_DIR/base/kustomization.yaml"
if ! grep -q 'statefulset.yaml' "$BASE_KUSTOMIZATION"; then
  sed -i '/- deployment.yaml/a\\  - statefulset.yaml' "$BASE_KUSTOMIZATION"
  echo "✅ Added statefulset.yaml to base/kustomization.yaml"
else
  echo "⏭️  statefulset.yaml already in base/kustomization.yaml"
fi

# Step 2: Add overlay-level patches to disable Deployment and PVC for this overlay
# Use a strategic merge patch + a JSON patch to remove deployment and PVC
PATCH_FILE="$OVERLAY_DIR/statefulset-patch.yaml"

cat > "$PATCH_FILE" <<'PATCH_EOF'
# Patches for StatefulSet mode — disables Deployment, PVC, and updates HPA
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hermes
$patch: delete
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hermes-data-pvc
$patch: delete
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hermes
spec:
  scaleTargetRef:
    kind: StatefulSet
    name: hermes
PATCH_EOF

echo "✅ Created $PATCH_FILE"

# Step 3: Add the patch file to the overlay's kustomization
if ! grep -q 'statefulset-patch.yaml' "$KUSTOMIZATION"; then
  # Add after the resources block
  sed -i '/^resources:/a\\  - statefulset-patch.yaml' "$KUSTOMIZATION"
  echo "✅ Added statefulset-patch.yaml to $KUSTOMIZATION"
else
  echo "⏭️  statefulset-patch.yaml already in $KUSTOMIZATION"
fi

echo ""
echo "Migration complete for overlay '$OVERLAY'."
echo ""
echo "Verify with:"
echo "  kubectl kustomize $OVERLAY_DIR | grep -A2 'kind:'"
echo ""
echo "Apply with:"
echo "  kubectl apply -k $OVERLAY_DIR"
echo ""
echo "To revert, remove statefulset-patch.yaml from the overlay and delete this file:"
echo "  rm $PATCH_FILE"
echo "  # Edit $KUSTOMIZATION to remove the statefulset-patch.yaml reference"