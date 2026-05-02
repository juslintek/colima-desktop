# AI Workloads

GPU-powered AI workloads on Apple Silicon via Krunkit.

## Requirements

- Apple Silicon Mac (M1+), macOS 13+, 8GB+ RAM
- Krunkit: `brew tap slp/krunkit && brew install krunkit`

## Getting Started

```bash
colima start --vm-type krunkit
colima model run gemma3
colima model run gemma3 "Explain quantum computing"
```

## Model Runners

- **Docker Model Runner** (default): Docker AI Registry + HuggingFace
- **Ramalama**: HuggingFace + Ollama registries

```bash
colima model run gemma3 --runner docker
colima model run gemma3 --runner ramalama
```

## Registries

```bash
# Docker AI Registry (default)
colima model run gemma3
# HuggingFace
colima model run hf.co/microsoft/Phi-3-mini-4k-instruct-gguf
# Ollama (ramalama only)
colima model run ollama://gemma3 --runner ramalama
```

## Serving Models

```bash
colima model serve gemma3
colima model serve gemma3 --port 9000
```

## Resource Recommendations

| Size | Min RAM | Recommended | Examples |
|------|---------|-------------|----------|
| Tiny (1-2B) | 4GB | 8GB | TinyLlama, Gemma 2B |
| Small (3-4B) | 8GB | 12GB | Phi-3 Mini |
| Medium (7-8B) | 12GB | 16GB | Llama 3.2, Mistral 7B |
| Large (13B+) | 16GB | 32GB | Phi-4, Llama 13B |

## Profiles for AI

```bash
colima start ai --vm-type krunkit --cpus 4 --memory 16 --disk 50
colima model run gemma3 -p ai
```

## Security

- Container isolation, CPU/memory limits, disk quotas
- Maximum isolation: `colima start --vm-type krunkit --mount=none`
