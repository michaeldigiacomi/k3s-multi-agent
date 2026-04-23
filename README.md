# k3s-multi-agent

Kustomize overlays for deploying multiple Hermes agents on a single k3s cluster, each using a different inference provider **and persona**. Your production Hermes instance in the `hermes` namespace is **never touched** — each overlay creates an isolated instance in its own namespace with its own PVC, secrets, and SOUL.md.

## Structure

```
k3s-multi-agent/
├── base/                        # Shared Hermes deployment template
│   ├── namespace.yaml
│   ├── deployment.yaml          # Includes SOUL.md initContainer injection
│   ├── service.yaml             # API endpoint per instance
│   ├── pvc.yaml                 # 10Gi persistent storage
│   ├── configmap-soul.yaml      # Default SOUL.md persona
│   └── kustomization.yaml
├── personas/                    # Ready-made personas
│   ├── sre.md                   # Site Reliability Engineer
│   ├── security.md              # Security specialist
│   └── devops.md                # DevOps / infrastructure automation
├── overlays/
│   ├── openai/                  # GPT-4o + default persona
│   ├── anthropic/               # Claude Sonnet 4 + Security persona
│   ├── groq/                    # Llama 3.3 70B + DevOps persona
│   └── ollama-local/            # Llama 3.1 8B + SRE persona
└── scripts/
    ├── spin-up.sh               # Deploy an overlay
    ├── tear-down.sh             # Remove an overlay
    └── list.sh                  # Show running instances
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
# Port-forward to the test instance
kubectl port-forward svc/hermes 8643:8642 -n hermes-openai

# Send a test request
curl http://localhost:8643/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hello!"}]}'
```

### 4. Tear down when done

```bash
# Remove the instance (deletes namespace, PVC, everything)
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

### Current Overlay → Persona Mapping

| Overlay | Provider | Model | Persona |
|---------|----------|-------|---------|
| `openai` | OpenAI | gpt-4o | Default |
| `anthropic` | Anthropic | claude-sonnet-4 | Security |
| `groq` | Groq | llama-3.3-70b-versatile | DevOps |
| `ollama-local` | Ollama (in-cluster) | llama3.1:8b | SRE |

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
6. Deploy: `./scripts/spin-up.sh mistral`

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

## Production Hermes

Your production Hermes instance lives in the `hermes` namespace and is **never modified** by this tool. The base manifests here are a template — overlays apply to brand-new namespaces. You can safely spin up and tear down test instances without any risk to production.