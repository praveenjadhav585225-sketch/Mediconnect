from functools import lru_cache
from sentence_transformers import SentenceTransformer

@lru_cache(maxsize=1)
def get_model(model_name: str = "all-MiniLM-L6-v2") -> SentenceTransformer:
    # Lazy, cached loading: the model is loaded only when /embed is first called.
    return SentenceTransformer(model_name, device="cpu")

def create_embedding(text: str, model_name: str) -> list[float]:
    model = get_model(model_name)
    vector = model.encode(
        text,
        normalize_embeddings=True,
        convert_to_numpy=True,
        show_progress_bar=False,
    )
    return vector.astype(float).tolist()
