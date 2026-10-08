import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import uvicorn
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("laya-server")

app = FastAPI(title="OpenGauge Laya Evaluator Server")

# Note: Update this to the exact HuggingFace repo for the Laya ModernBERT model
MODEL_NAME = "convai/laya-modernbert-large" 

logger.info(f"Initializing Laya server. Model target: {MODEL_NAME}")

# Global references for model and tokenizer
tokenizer = None
model = None
device = "cuda" if torch.cuda.is_available() else "cpu"

@app.on_event("startup")
async def load_model():
    global tokenizer, model
    try:
        logger.info(f"Loading tokenizer and model onto {device}...")
        # trust_remote_code=True is often required for new architectures like ModernBERT
        tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=True)
        model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME, trust_remote_code=True)
        model.eval()
        model.to(device)
        logger.info("Model loaded successfully.")
    except Exception as e:
        logger.error(f"Failed to load model. Ensure transformers>=4.48.0 is installed and model name is correct. Error: {e}")
        # We don't exit hard here so the server can still run and return 500s for debugging

class EvaluationRequest(BaseModel):
    prompt: str
    response: str

class EvaluationResult(BaseModel):
    score: int  # 0 to 100

@app.post("/score", response_model=EvaluationResult)
async def score_response(req: EvaluationRequest):
    if model is None or tokenizer is None:
        raise HTTPException(status_code=500, detail="Laya model is not loaded.")
    
    # Format input for BERT-style cross-encoding: [CLS] Prompt [SEP] Response [SEP]
    # ModernBERT supports up to 8192 context length
    inputs = tokenizer(
        req.prompt,
        req.response,
        return_tensors="pt",
        truncation=True,
        max_length=8192 
    )
    
    inputs = {k: v.to(device) for k, v in inputs.items()}

    with torch.no_grad():
        outputs = model(**inputs)
        logits = outputs.logits
        
        # Assuming Laya is a binary classifier where logit 0 represents the 'quality' or 'yes' class
        # We apply sigmoid to get a probability between 0.0 and 1.0
        prob = torch.sigmoid(logits[0][0]).item()
        
        # Convert probability to a 0-100 integer score
        score = int(prob * 100)
        
    return EvaluationResult(score=score)

if __name__ == "__main__":
    logger.info("Starting Uvicorn server on http://127.0.0.1:8000")
    uvicorn.run(app, host="127.0.0.1", port=8000)
