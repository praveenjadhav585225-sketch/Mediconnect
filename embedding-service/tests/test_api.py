import os
os.environ.setdefault("EMBEDDING_API_KEY", "test-secret")
from fastapi.testclient import TestClient
from app.main import app
import app.main as main

client = TestClient(app)

def test_health_does_not_load_model():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_embed_requires_api_key():
    response = client.post("/embed", json={"text": "A sufficiently long clinical case description."})
    assert response.status_code == 401

def test_embed_rejects_short_text():
    response = client.post(
        "/embed",
        headers={"X-API-Key": "test-secret"},
        json={"text": "short"},
    )
    assert response.status_code == 422

def test_embed_returns_384_dimensions(monkeypatch):
    monkeypatch.setattr(
        main,
        "create_embedding",
        lambda text, model_name: [0.0] * 384,
    )
    response = client.post(
        "/embed",
        headers={"X-API-Key": "test-secret"},
        json={"text": "Patient reports a sufficiently detailed case description."},
    )
    assert response.status_code == 200
    assert response.json()["dimensions"] == 384
    assert len(response.json()["embedding"]) == 384
