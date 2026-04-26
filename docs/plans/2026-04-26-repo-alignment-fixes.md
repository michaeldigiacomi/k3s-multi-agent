# k3s-multi-agent Repo Alignment Fixes

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Fix all bugs and inconsistencies found in the April 25 enhancements, bring the repo back to a clean, deployable state with accurate documentation.

**Architecture:** Fixes are grouped into 5 phases — critical CI blockers first, then workload consistency (Deployment/StatefulSet split-brain), then scripts, then policy/validation alignment, then documentation. Each task is a single, atomic change with a verification step.

**Tech Stack:** bash, YAML, Kustomize, GitHub Actions, conftest/Rego

---

## Phase 1: Critical CI Blockers

### Task 1: Fix broken shell syntax in agent-deploy.yml

**Objective:** Restore the `$(openssl rand -hex 32)` command that was corrupted to `*** rand -hex 32)`.

**Files:**
- Modify: `.github/workflows/agent-deploy.yml:195`

**Step 1: Apply the fix**

Change line 195 from:
```yaml
            API_KEY=*** rand -hex 32)
```
to:
```yaml
            API_KEY=$(openssl rand -hex 32)
```

**Step 2: Verify**

```bash
grep -n 'openssl rand' .github/workflows/agent-deploy.yml
# Expected: single line matching with correct $(openssl rand -hex 32) syntax
```

**Step 3: Commit**

```bash
git add .github/workflows/agent-deploy.yml
git commit -m "fix: restore openssl rand in agent-deploy.yml API key generation"
```

---

### Task 2: Fix malformed YAML heredoc in agent-deploy.yml

**Objective:** Fix the secret-generation heredoc that produces invalid YAML due to leading whitespace.

**Files:**
- Modify: `.github/workflows/agent-deploy.yml:213-245`

**Step 1: Rewrite the "Apply secrets" step**

Replace the entire `run: |` block in the "Apply secrets" step (lines 213-245) with:

```yaml
        run: |
          # Build a temporary secret manifest and apply it (idempotent, no delete)
          cat > /tmp/hermes-secrets.yaml <<SECRET_EOF
          apiVersion: v1
          kind: Secret
          metadata:
            name: hermes-secrets
            namespace: ${NS}
          type: Opaque
          stringData:
            API_SERVER_KEY: ${API_SERVER_KEY}
          SECRET_EOF

          if [ -n "$OPENAI_API_KEY" ]; then
            echo "  OPENAI_API_KEY: ${OPENAI_API_KEY}" >> /tmp/hermes-secrets.yaml
          fi
          if [ -n "$ANTHROPIC_API_KEY" ]; then
            echo "  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}" >> /tmp/hermes-secrets.yaml
          fi
          if [ -n "$GROQ_API_KEY" ]; then
            echo "  GROQ_API_KEY: ${GROQ_API_KEY}" >> /tmp/hermes-secrets.yaml
          fi
          if [ -n "$OLLAMA_API_KEY" ]; then
            echo "  OLLAMA_API_KEY: ${OLLAMA_API_KEY}" >> /tmp/hermes-secrets.yaml
          fi

          kubectl apply -f /tmp/hermes-secrets.yaml
          rm -f /tmp/hermes-secrets.yaml
```

**Step 2: Verify YAML validity**

```bash
# Check that the heredoc produces valid YAML structure
sed -n '/Apply secrets/,/kubectl apply/p' .github/workflows/agent-deploy.yml | head -20
# Confirm no leading whitespace in the heredoc content lines
grep -n 'SECRET_EOF\|apiVersion:\|kind:\|metadata:\|name:\|namespace:\|type:\|stringData:\|API_SERVER_KEY:' .github/workflows/agent-deploy.yml
```

**Step 3: Commit**

```bash
git add .github/workflows/agent-deploy.yml
git commit -m "fix: unindent secret heredoc in agent-deploy.yml to produce valid YAML"
```

---

### Task 3: Fix .DS_Store leak in CI overlay enumeration

**Objective:** Prevent `.DS_Store` from being treated as an overlay name in the detect job and spin-up/tilt scripts.

**Files:**
- Modify: `.github/workflows/agent-deploy.yml:55,67,86`
- Modify: `scripts/tilt-up.sh:12`
- Modify: `scripts/spin-up.sh:15,25`

**Step 1: Fix agent-deploy.yml — all 3 occurrences of `ls -d overlays/*/`**

Replace all 3 occurrences of:
```bash
ls -d overlays/*/ | xargs -n1 basename | jq -R . | jq -s .
```
with:
```bash
find overlays -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | jq -R . | jq -s .
```

There are occurrences at approximately lines 55, 67.

Also fix line 86 iteration:
```bash
          for overlay_dir in overlays/*/; do
```
Replace with:
```bash
          for overlay_dir in overlays/*/; do
            [[ "$overlay_dir" == *".DS_Store"* ]] && continue
```

**Step 2: Fix tilt-up.sh line 12**

Change:
```bash
  ls -1 "$ROOT_DIR/overlays/"
```
to:
```bash
  find "$ROOT_DIR/overlays/" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
```

**Step 3: Fix spin-up.sh lines 15 and 25**

Change both occurrences of:
```bash
  ls -1 "$ROOT_DIR/overlays/" 2>/dev/null | sed 's/^/  /'
```
to:
```bash
  find "$ROOT_DIR/overlays/" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sed 's/^/  /'
```

**Step 4: Add .DS_Store to .gitignore**

Append to `.gitignore`:
```
.DS_Store
```

**Step 5: Remove committed .DS_Store files**

```bash
git rm --cached .DS_Store overlays/.DS_Store 2>/dev/null || true
```

**Step 6: Verify**

```bash
# Confirm no .DS_Store tracked
git ls-files | grep .DS_Store
# Expected: empty output
grep -n 'find overlays' .github/workflows/agent-deploy.yml
# Expected: 3 matches
grep -n 'find.*overlays' scripts/tilt-up.sh scripts/spin-up.sh
# Expected: matches in both files
```

**Step 7: Commit**

```bash
git add .github/workflows/agent-deploy.yml scripts/tilt-up.sh scripts/spin-up.sh .gitignore
git rm --cached .DS_Store overlays/.DS_Store 2>/dev/null
git commit -m "fix: filter .DS_Store from overlay enumeration, add to gitignore"
```

---

### Task 4: Remove Rego from ci/policies kustomization

**Objective:** conftest policies are not Kubernetes resources — `kubectl kustomize ci/policies/` should not fail.

**Files:**
- Modify: `ci/policies/kustomization.yaml`

**Step 1: Fix the kustomization**

Replace `ci/policies/kustomization.yaml` with:
```yaml
# conftest policies are consumed by `conftest test --policy ci/policies/`,
# not by kubectl/kustomize. This kustomization is a no-op placeholder
# to satisfy directory-based tooling expectations.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# No resources — Rego files are not valid Kubernetes manifests.
# Use: conftest test --policy ci/policies/ <manifest.yaml>
```

**Step 2: Verify**

```bash
kubectl kustomize ci/policies/ > /dev/null
# Expected: success (no error)
```

**Step 3: Commit**

```bash
git add ci/policies/kustomization.yaml
git commit -m "fix: remove Rego from ci/policies kustomization (not a K8s resource)"
```

---

### Task 5: Add overlay-map.yaml to validate.yml path triggers

**Objective:** Changes to `overlay-map.yaml` affect persona routing and should trigger validation.

**Files:**
- Modify: `.github/workflows/validate.yml:4-9`

**Step 1: Add overlay-map.yaml to paths**

Change:
```yaml
on:
  pull_request:
    paths:
      - 'base/**'
      - 'overlays/**'
      - 'ci/policies/**'
      - 'personas/**'
```
to:
```yaml
on:
  pull_request:
    paths:
      - 'base/**'
      - 'overlays/**'
      - 'ci/policies/**'
      - 'personas/**'
      - 'overlay-map.yaml'
```

**Step 2: Verify**

```bash
grep 'overlay-map.yaml' .github/workflows/validate.yml
# Expected: 1 match in paths list
```

**Step 3: Commit**

```bash
git add .github/workflows/validate.yml
git commit -m "fix: add overlay-map.yaml to validate.yml path triggers"
```

---

## Phase 2: Workload Consistency (Deployment ↔ StatefulSet)

### Task 6: Rewrite migrate-to-statefulset.sh to work correctly

**Objective:** The current migration script has broken sed, missing $ROOT_DIR, doesn't handle PVC/HPA conflicts. Rewrite it properly.

**Files:**
- Modify: `scripts/migrate-to-statefulset.sh`

**Step 1: Rewrite the entire script**

```bash
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
  sed -i '/- deployment.yaml/a\  - statefulset.yaml' "$BASE_KUSTOMIZATION"
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
  sed -i '/^resources:/a\  - statefulset-patch.yaml' "$KUSTOMIZATION"
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
```

**Step 2: Verify**

```bash
bash -n scripts/migrate-to-statefulset.sh
# Expected: no syntax errors
```

**Step 3: Commit**

```bash
git add scripts/migrate-to-statefulset.sh
git commit -m "fix: rewrite migrate-to-statefulset.sh with correct kustomize approach"
```

---

### Task 7: Add statefulsets to RBAC Role

**Objective:** Agent should be able to read its own StatefulSet workload if migration is used.

**Files:**
- Modify: `base/rbac.yaml:9-11`

**Step 1: Add statefulsets to the Role**

Change:
```yaml
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list"]
```
to:
```yaml
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list"]
```

**Step 2: Verify**

```bash
grep 'statefulsets' base/rbac.yaml
# Expected: 1 match
```

**Step 3: Commit**

```bash
git add base/rbac.yaml
git commit -m "fix: add statefulsets to RBAC Role for StatefulSet migration support"
```

---

### Task 8: Fix PDB for single-replica deployments

**Objective:** `minAvailable: 1` with 1 replica blocks all voluntary eviction (kubectl drain deadlocks). Switch to `maxUnavailable: 1` which allows 1 pod to be disrupted.

**Files:**
- Modify: `base/poddisruptionbudget.yaml`

**Step 1: Change minAvailable to maxUnavailable**

Replace `base/poddisruptionbudget.yaml`:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: hermes
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: hermes
```

**Step 2: Verify**

```bash
grep -E 'minAvailable|maxUnavailable' base/poddisruptionbudget.yaml
# Expected: only maxUnavailable: 1
```

**Step 3: Commit**

```bash
git add base/poddisruptionbudget.yaml
git commit -m "fix: switch PDB to maxUnavailable to prevent drain deadlock at 1 replica"
```

---

### Task 9: Change Deployment strategy from Recreate to RollingUpdate

**Objective:** `Recreate` kills all pods before starting new ones (zero-downtime impossible). `RollingUpdate` is standard and consistent with StatefulSet.

**Files:**
- Modify: `base/deployment.yaml:7-8`

**Step 1: Change strategy**

Change:
```yaml
  strategy:
    type: Recreate
```
to:
```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
```

**Step 2: Verify**

```bash
grep -A3 'strategy:' base/deployment.yaml
# Expected: RollingUpdate with maxUnavailable: 0, maxSurge: 1
```

**Step 3: Commit**

```bash
git add base/deployment.yaml
git commit -m "fix: change Deployment strategy to RollingUpdate for zero-downtime updates"
```

---

### Task 10: Make spin-up.sh workload-kind aware

**Objective:** After migration to StatefulSet, `kubectl rollout restart deployment/hermes` fails. Detect the workload kind and restart the correct one.

**Files:**
- Modify: `scripts/spin-up.sh:78-84`

**Step 1: Replace the restart/restart-wait section**

Change lines 78-84:
```bash
# Restart to pick up new secret/config
echo "🔄 Restarting deployment..."
kubectl rollout restart deployment/hermes -n "$NAMESPACE"

# Wait for rollout
echo "⏳ Waiting for rollout..."
kubectl rollout status deployment/hermes -n "$NAMESPACE" --timeout=3m
```
to:
```bash
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
```

**Step 2: Verify**

```bash
bash -n scripts/spin-up.sh
grep 'WORKLOAD_KIND' scripts/spin-up.sh
# Expected: 3 matches
```

**Step 3: Commit**

```bash
git add scripts/spin-up.sh
git commit -m "fix: spin-up.sh auto-detects Deployment vs StatefulSet for rollout"
```

---

### Task 11: Make agent-deploy.yml workload-kind aware

**Objective:** Same as Task 10 but for CI. The "Restart deployment" and "Wait for deployment" steps need to detect the workload kind.

**Files:**
- Modify: `.github/workflows/agent-deploy.yml:249-268`

**Step 1: Replace the restart/wait/rollback steps**

Replace the "Restart deployment" step (lines 249-253) with:
```yaml
      - name: Restart workload to pick up new config
        env:
          NS: ${{ steps.ns.outputs.namespace }}
        run: |
          if kubectl get statefulset hermes -n "$NS" &>/dev/null; then
            WORKLOAD="statefulset"
          else
            WORKLOAD="deployment"
          fi
          kubectl rollout restart "$WORKLOAD/hermes" -n "$NS"
```

Replace the "Wait for deployment" step (lines 255-259) with:
```yaml
      - name: Wait for rollout
        env:
          NS: ${{ steps.ns.outputs.namespace }}
        run: |
          if kubectl get statefulset hermes -n "$NS" &>/dev/null; then
            WORKLOAD="statefulset"
          else
            WORKLOAD="deployment"
          fi
          kubectl rollout status "$WORKLOAD/hermes" -n "$NS" --timeout=3m
```

Replace the "Rollback on failure" step (lines 261-268) with:
```yaml
      - name: Rollback on failure
        if: failure()
        env:
          NS: ${{ steps.ns.outputs.namespace }}
        run: |
          if kubectl get statefulset hermes -n "$NS" &>/dev/null; then
            WORKLOAD="statefulset"
          else
            WORKLOAD="deployment"
          fi
          echo "::error::Deployment failed — rolling back $NS"
          kubectl rollout undo "$WORKLOAD/hermes" -n "$NS" || true
          kubectl rollout status "$WORKLOAD/hermes" -n "$NS" --timeout=2m || true
```

**Step 2: Verify**

```bash
grep -c 'WORKLOAD=' .github/workflows/agent-deploy.yml
# Expected: 3 (restart, wait, rollback)
```

**Step 3: Commit**

```bash
git add .github/workflows/agent-deploy.yml
git commit -m "fix: agent-deploy.yml auto-detects Deployment vs StatefulSet for rollout"
```

---

## Phase 3: Script & Policy Fixes

### Task 12: Make drift-check.sh StatefulSet-aware

**Objective:** Currently only checks Deployments. After migration, it would miss StatefulSet drift.

**Files:**
- Modify: `scripts/drift-check.sh`

**Step 1: Rewrite drift-check.sh**

```bash
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
```

**Step 2: Verify**

```bash
bash -n scripts/drift-check.sh
grep 'StatefulSet' scripts/drift-check.sh
# Expected: matches
```

**Step 3: Commit**

```bash
git add scripts/drift-check.sh
git commit -m "fix: drift-check.sh checks both Deployments and StatefulSets"
```

---

### Task 13: Fix tear-down.sh grep anchor

**Objective:** `grep 'namespace:'` can match unintended lines. Anchor it like spin-up.sh does.

**Files:**
- Modify: `scripts/tear-down.sh:24`

**Step 1: Fix the grep**

Change:
```bash
NAMESPACE=$(grep 'namespace:' "$OVERLAY_DIR/kustomization.yaml" | awk '{print $2}')
```
to:
```bash
NAMESPACE=$(grep '^namespace:' "$OVERLAY_DIR/kustomization.yaml" | awk '{print $2}')
```

**Step 2: Verify**

```bash
grep '^namespace:' scripts/tear-down.sh
# Expected: 1 match
```

**Step 3: Commit**

```bash
git add scripts/tear-down.sh
git commit -m "fix: anchor namespace grep in tear-down.sh"
```

---

### Task 14: Extend OPA policies to cover StatefulSets

**Objective:** All 5 conftest rules only gate on `input.kind == "Deployment"`. StatefulSet overlays bypass every check.

**Files:**
- Modify: `ci/policies/manifests.rego`

**Step 1: Rewrite manifests.rego**

```rego
package main

# Shared predicate: both Deployment and StatefulSet use the same pod template structure
is_workload(kind) {
  kind == "Deployment"
}
is_workload(kind) {
  kind == "StatefulSet"
}

deny[msg] {
  is_workload(input.kind)
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("Container %s in %s %s uses 'latest' tag", [container.name, input.kind, input.metadata.name])
}

deny[msg] {
  is_workload(input.kind)
  not input.spec.template.spec.containers[_].readinessProbe
  msg := sprintf("%s %s is missing readinessProbe", [input.kind, input.metadata.name])
}

deny[msg] {
  is_workload(input.kind)
  not input.spec.template.spec.containers[_].livenessProbe
  msg := sprintf("%s %s is missing livenessProbe", [input.kind, input.metadata.name])
}

deny[msg] {
  is_workload(input.kind)
  not input.spec.template.spec.securityContext.runAsNonRoot
  msg := sprintf("%s %s must set runAsNonRoot", [input.kind, input.metadata.name])
}

warn[msg] {
  is_workload(input.kind)
  not input.spec.template.spec.securityContext.fsGroup
  msg := sprintf("%s %s should set fsGroup", [input.kind, input.metadata.name])
}
```

**Step 2: Verify**

```bash
grep 'is_workload' ci/policies/manifests.rego | head -3
# Expected: 3 matches (2 definitions + usages)
grep 'input.kind ==' ci/policies/manifests.rego
# Expected: only in is_workload definitions, not in deny/warn rules
```

**Step 3: Commit**

```bash
git add ci/policies/manifests.rego
git commit -m "fix: extend conftest policies to cover both Deployment and StatefulSet"
```

---

### Task 15: Move hardcoded Discord config out of base deployment

**Objective:** `DISCORD_ALLOWED_USERS` and `DISCORD_HOME_CHANNEL` are hardcoded with specific IDs in the base Deployment template. They should be optional secret refs or overlay-level overrides.

**Files:**
- Modify: `base/deployment.yaml:175-178`
- Modify: `base/statefulset.yaml:177-180`

**Step 1: Change hardcoded values to optional secret refs**

In `base/deployment.yaml`, change:
```yaml
            - name: DISCORD_ALLOWED_USERS
              value: "1205965720018489344"
            - name: DISCORD_HOME_CHANNEL
              value: "1467952530150654186"
```
to:
```yaml
            - name: DISCORD_ALLOWED_USERS
              valueFrom:
                secretKeyRef:
                  name: hermes-secrets
                  key: DISCORD_ALLOWED_USERS
                  optional: true
            - name: DISCORD_HOME_CHANNEL
              valueFrom:
                secretKeyRef:
                  name: hermes-secrets
                  key: DISCORD_HOME_CHANNEL
                  optional: true
```

Apply the identical change to `base/statefulset.yaml`.

**Step 2: Verify**

```bash
grep -c 'DISCORD_ALLOWED_USERS\|DISCORD_HOME_CHANNEL' base/deployment.yaml base/statefulset.yaml
# Expected: 2 matches per file (name + secretKeyRef), no hardcoded value strings
grep '"1205965720018489344"' base/deployment.yaml base/statefulset.yaml
# Expected: no matches
```

**Step 3: Commit**

```bash
git add base/deployment.yaml base/statefulset.yaml
git commit -m "fix: move Discord IDs from hardcoded values to optional secret refs"
```

**Step 4: Update spin-up.sh to include Discord vars in temp env**

Add after line 58 (`echo "API_SERVER_KEY=$API_SERVER_KEY" > "$TMP_ENV"`):

```bash
# Include Discord config if provided in secrets.env
# (DISCORD_BOT_TOKEN, DISCORD_ALLOWED_USERS, DISCORD_HOME_CHANNEL)
```

This already works because `secrets.env` is appended to `$TMP_ENV` at line 62. No change needed — the secrets.env files already contain these values.

---

### Task 16: Fix agent-deploy.yml to include DISCORD_BOT_TOKEN in secrets

**Objective:** CI deploy step never writes `DISCORD_BOT_TOKEN` to the secret manifest.

**Files:**
- Modify: `.github/workflows/agent-deploy.yml:205-212`

**Step 1: Add DISCORD_BOT_TOKEN to env vars**

Add to the "Apply secrets" step `env:` block:
```yaml
          DISCORD_BOT_TOKEN: ${{ secrets.DISCORD_BOT_TOKEN || '' }}
          DISCORD_ALLOWED_USERS: ${{ secrets.DISCORD_ALLOWED_USERS || '' }}
          DISCORD_HOME_CHANNEL: ${{ secrets.DISCORD_HOME_CHANNEL || '' }}
```

**Step 2: Add conditional appends after the OLLAMA_API_KEY block**

After the OLLAMA_API_KEY conditional (line 244), add:
```bash
          if [ -n "$DISCORD_BOT_TOKEN" ]; then
            echo "  DISCORD_BOT_TOKEN: ${DISCORD_BOT_TOKEN}" >> /tmp/hermes-secrets.yaml
          fi
          if [ -n "$DISCORD_ALLOWED_USERS" ]; then
            echo "  DISCORD_ALLOWED_USERS: ${DISCORD_ALLOWED_USERS}" >> /tmp/hermes-secrets.yaml
          fi
          if [ -n "$DISCORD_HOME_CHANNEL" ]; then
            echo "  DISCORD_HOME_CHANNEL: ${DISCORD_HOME_CHANNEL}" >> /tmp/hermes-secrets.yaml
          fi
```

**Step 3: Add DISCORD secrets to the Required GitHub secrets table in README**

**Step 4: Verify**

```bash
grep 'DISCORD_BOT_TOKEN' .github/workflows/agent-deploy.yml | wc -l
# Expected: 2 (env declaration + conditional append)
```

**Step 5: Commit**

```bash
git add .github/workflows/agent-deploy.yml
git commit -m "fix: add Discord secrets to CI deploy workflow"
```

---

## Phase 4: Documentation Alignment

### Task 17: Update README file tree

**Objective:** Add missing files, fix inaccurate overlay provider labels.

**Files:**
- Modify: `README.md`

**Step 1: Add missing entries to file tree**

After `├── base/` section (line 31), replace `│   └── kustomization.yaml` with:
```
│   ├── statefulset.yaml       # StatefulSet alternative for stateful agents
│   └── kustomization.yaml
```

After the `scripts/` section, add:
```
│   ├── generate-dashboard.sh  # Regenerate Grafana dashboard JSON
│   └── list.sh                # Show running instances
```

After `└── .github/workflows/` section, add to the root tree:
```
├── overlay-map.yaml            # Maps overlays to persona files
├── Tiltfile                    # Tilt local dev configuration
└── .pre-commit-config.yaml     # Pre-commit hooks (persona + kustomize validation)
```

Also add `statefulset.yaml` line after deployment.yaml in the tree (currently missing).

**Step 2: Fix overlay → provider table**

Change:
```
| `appy` | Ollama | glm-5.1:cloud | Appy |
| `infred` | Ollama | glm-5.1:cloud | Infred |
```
to:
```
| `appy` | Custom (Ollama URL) | glm-5.1:cloud | Appy |
| `infred` | Custom (Ollama URL) | glm-5.1:cloud | Infred |
```

**Step 3: Add DISCORD secrets to the Required GitHub secrets table**

After the `OLLAMA_API_KEY` row, add:
```
| `DISCORD_BOT_TOKEN` | Discord bot token (for Discord-connected overlays, optional) |
| `DISCORD_ALLOWED_USERS` | Comma-separated Discord user IDs allowed to interact (optional) |
| `DISCORD_HOME_CHANNEL` | Default Discord channel ID (optional) |
```

**Step 4: Add note about StatefulSet migration and Velero**

In the "Adding a New Provider" section (after step 7), add:
```markdown
8. Add the new namespace to `dr/velero-schedule.yaml` in `includedNamespaces`
```

**Step 5: Verify**

```bash
grep -c 'statefulset.yaml\|overlay-map.yaml\|Tiltfile\|pre-commit-config\|DISCORD_BOT_TOKEN' README.md
# Expected: multiple matches for each
```

**Step 6: Commit**

```bash
git add README.md
git commit -m "docs: update README file tree, provider labels, and secret docs"
```

---

### Task 18: Update docs/scaling.md

**Objective:** Document the HPA target caveat, the new migration script behavior, and StatefulSet-specific notes.

**Files:**
- Modify: `docs/scaling.md`

**Step 1: Rewrite scaling.md**

```markdown
# Scaling Guide

## Option A: Deployment + HPA (Stateless Agents)

Use this if your agent does not persist state on the PVC.
- Keep `base/deployment.yaml` (default)
- Use `base/hpa.yaml` — HPA targets `kind: Deployment` by default
- Scale from 1-3 replicas automatically based on CPU utilization
- Uses a shared PVC (`hermes-data-pvc`) — all replicas share the same volume

## Option B: StatefulSet (Stateful Agents)

Use this if your agent requires persistent local state.
- Run `./scripts/migrate-to-statefulset.sh <overlay>` to enable
- This creates an overlay-specific patch file that:
  - Disables the Deployment (via `$patch: delete`)
  - Disables the shared PVC (StatefulSet uses `volumeClaimTemplates` instead)
  - Updates the HPA `scaleTargetRef` from `Deployment` to `StatefulSet`
- Each replica gets its own PVC (e.g., `hermes-data-hermes-0`, `hermes-data-hermes-1`)
- Stable network identity: `hermes-0.hermes`, `hermes-1.hermes`
- Manual scaling: `kubectl scale statefulset hermes --replicas=2 -n <namespace>`

### Migrating an Overlay from Deployment to StatefulSet

```bash
./scripts/migrate-to-statefulset.sh openai
```

This adds `statefulset.yaml` to `base/kustomization.yaml` and creates
`overlays/openai/statefulset-patch.yaml` which:
1. Deletes the Deployment (preventing both workloads from running)
2. Deletes the shared PVC (StatefulSet manages its own via volumeClaimTemplates)
3. Patches the HPA to target StatefulSet instead of Deployment

To revert: delete the patch file and remove its reference from the overlay's kustomization.yaml.

### Important Notes

- **PDB uses `maxUnavailable: 1`** — allows voluntary disruption even at 1 replica
- **HPA `maxReplicas: 3`** — matches the ResourceQuota `pods: 3` limit
- **ResourceQuota** — init containers count against pod quota during RollingUpdate
```

**Step 2: Verify**

```bash
wc -l docs/scaling.md
# Expected: ~40+ lines (expanded from 22)
```

**Step 3: Commit**

```bash
git add docs/scaling.md
git commit -m "docs: expand scaling.md with migration details and caveats"
```

---

### Task 19: Fix plan self-review label

**Objective:** The enhancements plan mislabels "Drift Detection" as "ArgoCD GitOps" in the self-review table.

**Files:**
- Modify: `docs/superpowers/plans/2026-04-25-k3s-multi-agent-enhancements.md`

**Step 1: Find and replace the label**

Search for `ArgoCD GitOps` in the self-review table and replace with `Drift Detection`.

**Step 2: Verify**

```bash
grep 'ArgoCD GitOps' docs/superpowers/plans/2026-04-25-k3s-multi-agent-enhancements.md
# Expected: no matches
grep 'Drift Detection' docs/superpowers/plans/2026-04-25-k3s-multi-agent-enhancements.md
# Expected: matches
```

**Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-04-25-k3s-multi-agent-enhancements.md
git commit -m "docs: fix plan self-review label from ArgoCD GitOps to Drift Detection"
```

---

### Task 20: Fix pre-commit-config regex for overlay-map.yaml

**Objective:** The kustomize-build hook should also trigger on `overlay-map.yaml` changes.

**Files:**
- Modify: `.pre-commit-config.yaml:13`

**Step 1: Extend the files regex**

Change:
```yaml
        files: '^(base|overlays)/.*\.yaml$'
```
to:
```yaml
        files: '^(base|overlays)/.*\.yaml$|^overlay-map\.yaml$'
```

**Step 2: Verify**

```bash
grep 'overlay-map' .pre-commit-config.yaml
# Expected: 1 match
```

**Step 3: Commit**

```bash
git add .pre-commit-config.yaml
git commit -m "fix: trigger kustomize-build hook on overlay-map.yaml changes"
```

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| **1: Critical CI** | 1-5 | Fix broken shell syntax, malformed heredoc, .DS_Store leak, Rego kustomization, validate triggers |
| **2: Workload** | 6-11 | Rewrite migrate script, RBAC, PDB, strategy, workload-aware spin-up and CI deploy |
| **3: Scripts/Policies** | 12-16 | Drift check StatefulSet support, grep anchor, OPA StatefulSet rules, Discord config, CI Discord secrets |
| **4: Docs** | 17-20 | README tree/provider table/secrets, scaling.md expansion, plan label fix, pre-commit regex |

**Total: 20 tasks across 4 phases.** All are independent within a phase (Phase 2 tasks 6-9 can be parallel, 10-11 depend on the concept but not the code). Phase 3 tasks are independent. Phase 4 is all documentation.