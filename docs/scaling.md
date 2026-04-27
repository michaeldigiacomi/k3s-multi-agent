# Scaling Guide

## Option A: Deployment + HPA (Stateless Agents)

Use this if your agent does not persist state on the PVC.
- Keep `base/deployment.yaml` (default)
- Use `base/hpa.yaml` — HPA targets `kind: Deployment` by default
- Scale from 1–3 replicas automatically based on CPU utilization
- Uses a shared PVC (`hermes-data-pvc`) — all replicas share the same volume
- **Deployment strategy:** `RollingUpdate` with `maxUnavailable: 0` and `maxSurge: 1` for zero-downtime updates

## Option B: StatefulSet (Stateful Agents)

Use this if your agent requires persistent local state.
- Run `./scripts/migrate-to-statefulset.sh <overlay>` to enable
- This creates an overlay-specific patch file (`statefulset-patch.yaml`) that:
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

- **PDB uses `maxUnavailable: 1`** — allows voluntary disruption even at 1 replica (prevents drain deadlocks)
- **HPA `maxReplicas: 3`** — matches the ResourceQuota `pods: 3` limit
- **ResourceQuota** — init containers count against pod quota during RollingUpdate
- **Discord config** — `DISCORD_ALLOWED_USERS` and `DISCORD_HOME_CHANNEL` are now optional secret refs (not hardcoded in base manifests)