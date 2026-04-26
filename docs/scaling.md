# Scaling Guide

## Option A: Deployment + HPA (Stateless Agents)

Use this if your agent does not persist state on the PVC.
- Keep `base/deployment.yaml`
- Use `base/hpa.yaml`
- Scale from 1-3 replicas automatically based on CPU utilization

## Option B: StatefulSet (Stateful Agents)

Use this if your agent requires persistent local state.
- Replace `base/deployment.yaml` reference with `base/statefulset.yaml`
- Each replica gets its own PVC (e.g., `hermes-data-hermes-0`, `hermes-data-hermes-1`)
- Stable network identity: `hermes-0.hermes`, `hermes-1.hermes`
- Manual scaling: `kubectl scale statefulset hermes --replicas=2 -n <namespace>`

### Migrating an Overlay from Deployment to StatefulSet

```bash
./scripts/migrate-to-statefulset.sh openai
```
