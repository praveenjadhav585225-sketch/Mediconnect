from fastapi import FastAPI, Header, HTTPException, Depends
from app.config import API_KEY, MODEL_NAME
from app.schemas import EmbedRequest, EmbedResponse
from app.model import create_embedding, get_model

app = FastAPI(
    title="MediConnect Embedding Service",
    version="1.0.0",
    description="Generates text embeddings for semantic case matching. It does not diagnose or recommend treatment.",
)

def require_api_key(x_api_key: str | None = Header(default=None)):
    if not API_KEY:
        raise HTTPException(status_code=503, detail="Embedding service API key is not configured")
    if x_api_key is None or x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")

@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_NAME, "model_loaded": get_model.cache_info().currsize > 0}

@app.post("/embed", response_model=EmbedResponse, dependencies=[Depends(require_api_key)])
def embed(payload: EmbedRequest):
    try:
        embedding = create_embedding(payload.text, MODEL_NAME)
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Embedding model is unavailable") from exc
    if len(embedding) != 384:
        raise HTTPException(status_code=500, detail=f"Expected 384 dimensions, received {len(embedding)}")
    return EmbedResponse(model=MODEL_NAME, dimensions=len(embedding), embedding=embedding)
