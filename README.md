# k3s-multi-agent

Kustomize overlays for deploying multiple Hermes agents on a single k3s cluster behind **Tailscale** (no public access). Each overlay uses a different inference provider **and persona**. Your production Hermes instance in the `hermes` namespace is **never touched** — each overlay creates an isolated instance in its own namespace with its own PVC, secrets, and SOUL.md.

## Network Model

This cluster lives on a **private Tailscale network** with no public internet access. All access is through Tailscale IPs or `kubectl port-forward`.

- **No public DNS** — hostnames do not resolve on the public internet
- **No Let's Encrypt** — cert-manager with public CAs will not work
- **Transport encryption** — Tailscale's WireGuard tunnel encrypts all traffic between nodes
- **Access patterns:** `kubectl port-forward` (dev), NodePort on Tailscale IPs (prod-like), or Tailscale Kubernetes Operator (best long-term)

## Structure

```
k3s-multi-agent/
├── base/                        # Shared Hermes deployment template
│   ├── namespace.yaml
│   ├── serviceaccount.yaml      # Dedicated SA per overlay
│   ├── rbac.yaml                # Minimal Role + RoleBinding
│   ├── networkpolicy.yaml       # Default-deny + scoped allows
│   ├── resourcequota.yaml       # Per-namespace quotas
│   ├── limitrange.yaml          # Default container limits
│   ├── poddisruptionbudget.yaml # Prevent eviction during drains
│   ├── pvc.yaml
│   ├── configmap-soul.yaml      # Default SOUL.md persona
│   ├── deployment.yaml          # Hardened: probes, seccontext, pinned tools
│   ├── service.yaml
│   ├── ingress.yaml             # OPTIONAL — see file comments
│   ├── hpa.yaml                 # Horizontal Pod Autoscaler
│   └── kustomization.yaml
├── personas/                    # Reusable persona definitions
│   ├── default.md
│   ├── sre.md
│   ├── security.md
│   ├── devops.md
│   ├── appy.md
│   └── infred.md
├── overlays/
│   ├── openai/                  # GPT-4o + default persona
│   ├── anthropic/               # Claude Sonnet 4 + Security persona
│   ├── groq/                    # Llama 3.3 70B + DevOps persona
│   ├── ollama-local/            # Llama 3.1 8B + SRE persona
│   ├── appy/                    # glm-5.1:cloud + App Architect persona
│   └── infred/                  # glm-5.1:cloud + Infra Architect persona
├── scripts/
│   ├── spin-up.sh               # Deploy an overlay
│   ├── tear-down.sh             # Remove an overlay (triggers Velero backup)
│   ├── list.sh                  # Show running instances
│   ├── sync-personas.sh         # Sync personas to overlays
│   ├── validate-persona.sh      # Validate persona structure
│   ├── drift-check.sh           # Compare cluster state to git
│   ├── tilt-up.sh               # Start Tilt for local dev
│   └── migrate-to-statefulset.sh # Convert overlay to StatefulSet
├── observability/               # Prometheus + Grafana
│   ├── servicemonitor.yaml
│   ├── grafana-dashboard.json
│   └── kustomization.yaml
├── ci/policies/                 # conftest Rego policies
│   └── manifests.rego
├── dr/                          # Velero backup schedule
│   ├── velero-schedule.yaml
│   └── kustomization.yaml
├── docs/
│   └── scaling.md               # Deployment vs StatefulSet guide
└── .github/workflows/
    ├── agent-deploy.yml           # Main CI/CD pipeline
    ├── validate.yml               # PR validation (kube-score + conftest)
    └── drift-detection.yml      # Scheduled drift checks
```

## Quick Start

### 1. Spin up a test instance

```bash
# Deploy OpenAI-backed Hermes
./scripts/spin-up.sh openai

# Deploy Anthropic-backed Hermes
./scripts/spin-up.sh anthropic

# Deploy Groq-backed Hermes
./scripts/spin-up.sh groq

# Deploy local Ollama-backed Hermes
./scripts/spin-up.sh ollama-local
```

### 2. Set up secrets

Each overlay needs API keys. After the first `spin-up`, create the secret:

```bash
# Copy the example and fill in your keys
cp overlays/openai/secrets.env.example overlays/openai/secrets.env
# Edit secrets.env with your actual keys...

# Create the Kubernetes secret
kubectl create secret generic hermes-secrets \
  --from-env-file=overlays/openai/secrets.env \
  -n hermes-openai

# Restart the pod to pick up the secret
kubectl rollout restart deployment/hermes -n hermes-openai
```

### 3. Test the agent

```bash
# Port-forward to the test instance (simplest, development)
kubectl port-forward svc/hermes 8643:8642 -n hermes-openai

# Send a test request
curl http://localhost:8643/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hello!"}]}'
```

### 4. External access on Tailscale (optional)

Since there is no public internet, use one of these patterns:

**A. NodePort (production-like)**

Patch the service to `type: NodePort` in your overlay kustomization, then access via any node's Tailscale IP:

```
http://<node-tailscale-ip>:<nodePort>
```

**B. Tailscale Kubernetes Operator (best long-term)**

Install the [Tailscale Kubernetes operator](https://tailscale.com/kb/1236/kubernetes-operator). It creates a Tailscale machine per service with automatic HTTPS using Tailscale's internal CA. Uncomment `base/ingress.yaml` and change `ingressClassName` to `tailscale`.

### 5. Tear down when done

```bash
# Remove the instance (deletes namespace, PVC, everything)
# Automatically triggers a Velero backup before deletion
./scripts/tear-down.sh openai
```

## Personas

Each overlay can inject a custom **SOUL.md** that defines the agent's personality, behavior, and expertise. The SOUL.md is loaded by Hermes at startup and shapes how the agent thinks and responds.

### Built-in Personas

| Persona | File | Description |
|---------|------|-------------|
| **Default** | `base/configmap-soul.yaml` | General-purpose Hermes assistant |
| **SRE** | `personas/sre.md` | Site Reliability Engineer — monitors, responds to incidents, manages SLOs |
| **Security** | `personas/security.md` | Security specialist — vulnerability assessment, threat modeling, hardening |
| **DevOps** | `personas/devops.md` | Infrastructure automation — CI/CD, pipelines, GitOps, environment management |
| **Appy** | `personas/appy.md` | Application Architect — design patterns, APIs, microservices |
| **Infred** | `personas/infred.md` | Infrastructure Architect — cloud-native infrastructure, platform engineering |

### Current Overlay → Persona Mapping

| Overlay | Provider | Model | Persona |
|---------|----------|-------|---------|
| `openai` | OpenAI | gpt-4o | Default |
| `anthropic` | Anthropic | claude-sonnet-4 | Security |
| `groq` | Groq | llama-3.3-70b-versatile | DevOps |
| `ollama-local` | Ollama (in-cluster) | llama3.1:8b | SRE |
| `appy` | Ollama | glm-5.1:cloud | Appy |
| `infred` | Ollama | glm-5.1:cloud | Infred |

### How Personas Work

The deployment includes an `inject-soul` initContainer that:
1. Reads the SOUL.md from a ConfigMap
2. Writes it to `/opt/data/SOUL.md` on the persistent volume
3. Hermes loads it at startup as its system prompt

To change an overlay's persona, edit its `kustomization.yaml` and update the `configMapGenerator` file path:

```yaml
configMapGenerator:
  - name: hermes-soul
    behavior: replace
    files:
      - SOUL.md=../../personas/sre.md    # Change this line
```

### Creating a Custom Persona

1. Create a new `.md` file in `personas/` (e.g., `personas/data-scientist.md`)
2. Define the persona — identity, responsibilities, communication style, principles
3. Reference it in your overlay's `kustomization.yaml`:

```yaml
configMapGenerator:
  - name: hermes-soul
    behavior: replace
    files:
      - SOUL.md=../../personas/data-scientist.md
```

4. Apply: `kubectl apply -k overlays/your-overlay/`

## Adding a New Provider

1. Create a new directory under `overlays/` (e.g., `overlays/mistral/`)
2. Copy `kustomization.yaml` from an existing overlay
3. Update the namespace and env patches (provider, model, base URL)
4. Choose or create a persona
5. Create a `secrets.env.example` with required keys
6. Add to `overlay-map.yaml`: `mistral: default.md`
7. Deploy: `./scripts/spin-up.sh mistral`

## Isolation Guarantees

Each overlay creates a fully isolated instance:

| Resource | Per-overlay | Production |
|----------|------------|------------|
| **Namespace** | `hermes-openai`, `hermes-anthropic`, etc. | `hermes` |
| **PVC** | Separate 10Gi volume per instance | Untouched |
| **Secrets** | Each provider's API key in its own namespace | Untouched |
| **SOUL.md** | Custom persona per instance | Untouched |
| **Config** | Own model, provider, base URL | Untouched |
| **Pod** | Isolated — no shared state | Untouched |
| **NetworkPolicy** | Default-deny + scoped egress | Untouched |
| **ServiceAccount** | Dedicated SA with minimal RBAC | Untouched |
| **ResourceQuota** | Caps CPU/memory/PVCs per namespace | Untouched |

## CI/CD Pipeline

A single GitHub Actions workflow manages all agents. It uses **matrix jobs** — one job per overlay, running in parallel when multiple agents change.

### How it works

```
Push to main
  │
  ├─ detect
  │   ├─ Detects changed overlays BEFORE any commit
  │   ├─ Syncs persona files → overlay SOUL.md
  │   └─ Outputs list of changed overlays (e.g. ["openai", "groq"])
  │
  ├─ validate (parallel matrix)
  │   ├─ runner 1: kube-score + conftest + kustomize ✓
  │   └─ runner 2: kube-score + conftest + kustomize ✓
  │
  └─ deploy (parallel matrix)
      ├─ runner 1: apply openai overlay + stable secrets + restart
      └─ runner 2: apply groq overlay + stable secrets + restart
```

### Triggers

| Trigger | What happens |
|---------|-------------|
| Push to `main` (any overlay/persona/base change) | Detects which overlays changed, validates, deploys only those |
| Push to `main` (base/ or workflow change) | Rebuilds **all** overlays |
| Push to `main` (persona change in `personas/`) | Syncs persona → overlays per `overlay-map.yaml`, rebuilds affected overlays |
| Manual: Deploy | Actions → Run workflow → pick overlay (or empty = all) → deploy |
| Manual: Teardown | Actions → Run workflow → action: teardown → pick overlay → deletes namespace |

### Adding a new agent

1. Create overlay: `overlays/my-provider/kustomization.yaml` + `SOUL.md`
2. Add entry to `overlay-map.yaml`: `my-provider: default.md`
3. Push — the workflow detects the new overlay and deploys it

### Changing a persona

Edit `personas/sre.md` → push → the workflow:
1. Reads `overlay-map.yaml` to find which overlays use `sre.md`
2. Copies `personas/sre.md` → `overlays/ollama-local/SOUL.md`
3. Commits the sync
4. Deploys only `ollama-local`

### Swapping personas

Change the mapping in `overlay-map.yaml`:

```yaml
# Before:
openai: default.md

# After:
openai: sre.md
```

Push and the openai agent will rebuild with the SRE persona.

### Required GitHub secrets

| Secret | Description |
|--------|-------------|
| `KUBE_CONFIG` | k3s kubeconfig (base64) |
| `TAILSCALE_AUTH_KEY` | Tailscale auth key for k8s connectivity |
| `OPENAI_API_KEY` | OpenAI API key (for openai overlay) |
| `ANTHROPIC_API_KEY` | Anthropic API key (for anthropic overlay) |
| `GROQ_API_KEY` | Groq API key (for groq overlay) |
| `OLLAMA_API_KEY` | Ollama API key (for ollama-local overlay, optional) |

Provider API keys only need to be set for overlays you're actually using. The pipeline reuses existing `API_SERVER_KEY` from each namespace — no need to set it manually.

## Security & Observability

### Network Isolation

- **Default-deny NetworkPolicy** — pods without an explicit allow policy get no traffic
- **Scoped ingress** — only port 8642 from the same namespace
- **Scoped egress** — DNS, Ollama service, and provider APIs on 443 only
- **Cross-namespace blocked** — overlays cannot reach each other or production

### RBAC

- Dedicated `ServiceAccount` per overlay
- Minimal `Role` (get/list on pods, services, configmaps, events, PVCs, deployments)
- No cluster-wide permissions

### Probes

- `startupProbe` — waits up to 5 minutes for the agent to start
- `readinessProbe` — prevents traffic to unready pods
- `livenessProbe` — restarts crashed pods after 3 failures

### Drift Detection

A scheduled workflow runs every 6 hours comparing live cluster state to git manifests. If someone manually `kubectl edit`s a resource, it opens a GitHub issue.

```bash
# Check drift manually
./scripts/drift-check.sh
```

### Backup

Velero runs daily at 2 AM backing up all overlay PVCs, secrets, and configmaps. `tear-down.sh` triggers a pre-delete backup automatically.

### Scaling

- **Deployment + HPA** (default): Scales 1-3 replicas based on CPU. Use for stateless agents.
- **StatefulSet** (optional): Stable network identity + individual PVCs per replica. Use for stateful agents.

```bash
# Migrate an overlay to StatefulSet
./scripts/migrate-to-statefulset.sh openai
```

## Local Development

Use Tilt for live-reload local development without CI round-trips:

```bash
# Start OpenAI overlay with hot-reload
./scripts/tilt-up.sh openai

# Tilt will:
# 1. Sync personas to overlays
# 2. Build kustomize manifests
# 3. Apply to your local cluster
# 4. Port-forward :8642 automatically
# 5. Hot-reload on persona or manifest changes
```

## Production Hermes

Your production Hermes instance lives in the `hermes` namespace and is **never modified** by this tool. The base manifests here are a template — overlays apply to brand-new namespaces. You can safely spin up and tear down test instances without any risk to production.