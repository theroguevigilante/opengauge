# OpenGauge

A lightweight CLI for benchmarking and evaluating open-weight language models.

## Usage

```bash
zig build
./zig-out/bin/opengauge run config.json
./zig-out/bin/opengauge profile # or opengauge list
```

Example `config.json` with evaluation:

```json
{
  "model": "smollm2:135m",
  "backend": "ollama",
  "base_url": "http://localhost:11434",
  "prompt": "Explain gravity in one sentence.",
  "max_tokens": 64,
  "runs": 3,
  "warmup": 1,
  "evaluator": {
    "url": "http://127.0.0.1:8000/score"
  }
}
```

## Features

* **Backends**: `llama.cpp`, `ollama`, and OpenAI-compatible endpoints
* **Metrics**: TTFT (time-to-first-token), mean, p50, p90 latency, and tokens/sec over configurable runs
* **Laya Evaluator**: automated response quality scoring via Convai Innovations Laya (ModernBERT decision model)
* **Leaderboard & Profile Registry**: saves tested models to `~/.opengauge/profile.json` and renders an aligned comparison table (`opengauge profile`)
* **Dependency-free**: pure Zig standard library only

## License

[AGPL-3.0](LICENSE)
