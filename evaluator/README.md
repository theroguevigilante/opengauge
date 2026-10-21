# Evaluator

Local FastAPI server running [Laya](https://huggingface.co/convaiinnovations/laya) (`convaiinnovations/laya`, ModernBERT-large classifier) for deterministic response quality scoring.

OpenGauge hits this endpoint after each benchmark run when `evaluator` is configured in `config.json`.

## Requirements

- Python 3.10+
- Hugging Face weights (~840 MB, downloaded on first start to `~/.cache/huggingface/hub/`)

## Quickstart

```bash
cd evaluator
uv venv .venv && source .venv/bin/activate
uv pip install -r requirements.txt
python server.py
```

*(Or use `python3 -m venv .venv` and `pip install -r requirements.txt`)*

The server listens on `127.0.0.1:8000`.

## Endpoints

### `GET /health`
Verifies server and model status.

```bash
curl http://127.0.0.1:8000/health
# {"status":"ok","model_loaded":true}
```

### `POST /score`
Scores a model response against the prompt on a 0–100 scale.

```bash
curl -X POST http://127.0.0.1:8000/score \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Explain gravity in one sentence.", "response": "Gravity is the curvature of spacetime caused by mass and energy."}'
# {"score":84}
```

Scoring maps Laya's 0–4 rubric (nonsense → excellent) to a normalized 0–100 integer.
