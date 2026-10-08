# OpenGauge Evaluator (Laya / ModernBERT)

This directory contains the Python API server that hosts the **Laya** decision model. Laya is a non-autoregressive "System One" classifier based on the ModernBERT architecture.

Because Laya is an encoder (BERT-style) rather than a generative LLM, it cannot be run in standard text-generation endpoints like Ollama or llama.cpp. Instead, we host it locally in this lightweight FastAPI server. OpenGauge will send HTTP POST requests to this server during the benchmark to get deterministic quality scores.

## Setup

1. **Create a virtual environment (optional but recommended):**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

2. **Install dependencies:**
   *(Note: ModernBERT requires `transformers >= 4.48.0`)*
   ```bash
   pip install -r requirements.txt
   ```

3. **Verify the Model Target:**
   Open `server.py` and ensure `MODEL_NAME` points to the correct HuggingFace repository for Laya (e.g., `"convai/laya-modernbert-large"`).

## Running the Server

Start the server on `localhost:8000`:
```bash
python server.py
```

The first time you run this, it will download the ~421M parameter ModernBERT weights from HuggingFace to your local cache.

## Usage

Once running, OpenGauge will automatically hit this endpoint when configured. You can test it manually with curl:

```bash
curl -X POST http://127.0.0.1:8000/score \
     -H "Content-Type: application/json" \
     -d '{"prompt": "Write a python loop", "response": "def loop():\n  pass"}'
```

Expected output:
```json
{"score": 85}
```
