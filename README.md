# k3s-multi-agent

Kustomize overlays for deploying multiple Hermes agents on a single k3s cluster, each using a different inference provider. Your production Hermes instance in the `hermes` namespace is **never touched** — each overlay creates an isolated instance in its own namespace with its own PVC, secrets, and config.

## Structure

```
k3s-multi-agent/
├── base/                        # Shared Hermes deployment template
│   ├── namespace.yaml
│   ├── deployment.yaml          # Parameterized (provider, model, keys)
│   ├── service.yaml             # API endpoint per instance
│   ├── pvc.yaml                 # 10Gi persistent storage
│   └── kustomization.yaml
├── overlays/
│   ├── openai/                  # Test with OpenAI (GPT-4o)
│   ├── anthropic/               # Test with Anthropic (Claude Sonnet 4)
│   ├── groq/                    # Test with Groq (Llama 3.3 70B)
│   └── ollama-local/            # Test with local Ollama (Llama 3.1 8B)
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

## Isolation Guarantees

Each overlay creates a fully isolated instance:

| Resource | Per-overlay | Production |
|----------|------------|------------|
| **Namespace** | `hermes-openai`, `hermes-anthropic`, etc. | `hermes` |
| **PVC** | Separate 10Gi volume per instance | Untouched |
| **Secrets** | Each provider's API key in its own namespace | Untouched |
| **Config** | Own model, provider, base URL | Untouched |
| **Pod** | Isolated — no shared state | Untouched |

## Adding a New Provider

1. Create a new directory under `overlays/` (e.g., `overlays/mistral/`)
2. Copy `kustomization.yaml` from an existing overlay
3. Update the namespace and env patches (provider, model, base URL)
4. Create a `secrets.env.example` with required keys
5. Deploy: `./scripts/spin-up.sh mistral`

## Production Hermes

Your production Hermes instance lives in the `hermes` namespace and is **never modified** by this tool. The base manifests here are a template — overlays apply to brand-new namespaces. You can safely spin up and tear down test instances without any risk to production.

## Available Overlays

| Overlay | Provider | Model | Namespace |
|---------|----------|-------|-----------|
| `openai` | OpenAI | gpt-4o | hermes-openai |
| `anthropic` | Anthropic | claude-sonnet-4 | hermes-anthropic |
| `groq` | Groq | llama-3.3-70b-versatile | hermes-groq |
| `ollama-local` | Ollama (in-cluster) | llama3.1:8b | hermes-ollama-local |