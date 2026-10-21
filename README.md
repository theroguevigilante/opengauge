# OpenGauge

Dependency-free Zig CLI for benchmarking local LLM backends (`ollama`, `llama.cpp`, and OpenAI-compatible endpoints) with latency profiling, throughput metrics, and automated quality scoring.

## Build

Requires Zig 0.16.0.

```bash
zig build
```

Run tests:
```bash
zig build test
```

## Quickstart

Run a benchmark using a config:

```bash
./zig-out/bin/opengauge run configs/smollm2_135m.json
```

Example output:

```
backend    model             runs      TTFT       mean        p50        p90     tok/s    quality
─────────────────────────────────────────────────────────────────────────────────────────────────
ollama     smollm2:135m         3      23ms      460ms      502ms      518ms      50.0     76/100
```

View saved profile leaderboard across all runs:

```bash
./zig-out/bin/opengauge profile
# or: ./zig-out/bin/opengauge list
```

Benchmark capabilities are persisted to `~/.opengauge/profile.json`.

## Configuration

Configs are JSON files. Ready-to-run examples live in [`configs/`](configs/):

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

- `backend`: `"ollama"`, `"llama.cpp"`, or `"openai"`
- `base_url`: endpoint root (e.g. `http://localhost:11434`, `http://localhost:8080`, `https://api.openai.com`)
- `warmup`: number of untimed warmup runs before measurement
- `runs`: number of timed iterations to collect stats (mean, p50, p90, TTFT)
- `evaluator`: optional. Points to the local Laya evaluator service (`evaluator/`) to append a 0–100 quality score.

## Evaluator (Optional)

The response quality scoring service is located in [`evaluator/`](evaluator/). It runs a ModernBERT decision model (`convaiinnovations/laya`) locally via FastAPI. See [`evaluator/README.md`](evaluator/README.md) for setup.

## License

[AGPL-3.0](LICENSE)
