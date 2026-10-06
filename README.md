# OpenGauge

A lightweight CLI for benchmarking and evaluating open-weight language models.

## Usage

```bash
zig build
./zig-out/bin/opengauge run config.json
```

Example `config.json`:

```json
{
  "model": "llama-3-8b-instruct",
  "backend": "ollama",
  "base_url": "http://localhost:11434",
  "prompt": "What is the capital of France?",
  "max_tokens": 256,
  "runs": 5,
  "warmup": 1
}
```

## Features

* **Backends**: `llama.cpp`, `ollama`, and OpenAI-compatible endpoints
* **Stats**: mean, p50, p90 latency, and tokens/sec over configurable runs
* **Dependency-free**: Zig standard library only

## License

[AGPL-3.0](LICENSE)
