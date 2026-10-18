# OpenGauge Evaluator (Laya / ModernBERT)

This directory contains the Python API server that hosts the **Laya** decision model. Laya is a non-autoregressive "System One" classifier based on the ModernBERT architecture.

Because Laya is an encoder (BERT-style) rather than a generative LLM, it cannot be run in standard text-generation endpoints like Ollama or llama.cpp. Instead, we host it locally in this lightweight FastAPI server. OpenGauge will send HTTP POST requests to this server during the benchmark to get deterministic quality scores.

## Setup

1. **Create a virtual environment:**
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   # or with uv:
   # uv pip install -r requirements.txt
   ```

3. **Model Weights:**
   The server automatically loads the official weights from HuggingFace (`convaiinnovations/laya`, ~843 MB ModernBERT-large classifier) on first run and caches them in `~/.cache/huggingface/hub/`.

## Running the Server

Start the server on `127.0.0.1:8000`:
```bash
python server.py
# or directly with the virtualenv:
# .venv/bin/python server.py
```

## Endpoints

### Health Check

```bash
curl -s http://127.0.0.1:8000/health
```

Expected output:
```json
{"status":"ok","model_loaded":true}
```

### Quality Scoring

```bash
curl -X POST http://127.0.0.1:8000/score \
     -H "Content-Type: application/json" \
     -d '{"prompt": "Explain gravity in one sentence.", "response": "Gravity is the curvature of spacetime caused by mass and energy attracting objects toward one another."}'
```

Expected output:
```json
{"score": 84}
```
