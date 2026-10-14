import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn
import laya

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("laya-server")

app = FastAPI(title="OpenGauge Laya Evaluator Server")

agent = None

@app.on_event("startup")
async def startup_event():
    global agent
    try:
        logger.info("Loading Laya model (convaiinnovations/laya)...")
        agent = laya.load("convaiinnovations/laya")
        logger.info("Laya model loaded successfully.")
    except Exception as e:
        logger.error(f"Failed to load Laya model: {e}")

class EvaluationRequest(BaseModel):
    prompt: str
    response: str

class EvaluationResult(BaseModel):
    score: int  # 0 to 100

@app.post("/score", response_model=EvaluationResult)
async def score_response(req: EvaluationRequest):
    if agent is None:
        raise HTTPException(status_code=500, detail="Laya model is not loaded yet.")

    state = f"Prompt: {req.prompt}\nResponse: {req.response}"
    questions = {
        "quality": {
            "type": "score",
            "range": [0, 100]
        }
    }

    try:
        res = agent.predict(state, questions)
        # Extract score from answers
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
