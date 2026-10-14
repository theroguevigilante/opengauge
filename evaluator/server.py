import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn
import laya

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("laya-server")

agent = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global agent
    try:
        logger.info("Loading Laya model (convaiinnovations/laya)...")
        agent = laya.load("convaiinnovations/laya")
        logger.info("Laya model loaded successfully.")
    except Exception as e:
        logger.error(f"Failed to load Laya model: {e}")
    yield

app = FastAPI(title="OpenGauge Laya Evaluator Server", lifespan=lifespan)

class EvaluationRequest(BaseModel):
    prompt: str
    response: str

class EvaluationResult(BaseModel):
    score: int  # 0 to 100

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model_loaded": agent is not None
    }

@app.post("/score", response_model=EvaluationResult)
async def score_response(req: EvaluationRequest):
    if agent is None:
        raise HTTPException(status_code=503, detail="Laya model is not loaded yet.")

    state = f"Prompt: {req.prompt}\nResponse: {req.response}"
    questions = {
        "quality": {
            "type": "score",
            "range": [0, 100]
        }
    }

    try:
        res = agent.predict(state, questions)
        answers = res.get("answers", {})
        quality_entry = answers.get("quality", {})
        score = quality_entry.get("score", 50)
        return EvaluationResult(score=int(score))
    except Exception as e:
        logger.error(f"Error during scoring: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    logger.info("Starting Laya Evaluator server on http://127.0.0.1:8000")
    uvicorn.run(app, host="127.0.0.1", port=8000)
