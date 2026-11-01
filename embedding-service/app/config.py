import os
from pathlib import Path
from dotenv import load_dotenv

SERVICE_DIR = Path(__file__).resolve().parents[1]
load_dotenv(SERVICE_DIR / ".env")

API_KEY = os.getenv("EMBEDDING_API_KEY", "")
MODEL_NAME = os.getenv("MODEL_NAME", "all-MiniLM-L6-v2")
MAX_TEXT_LENGTH = int(os.getenv("MAX_TEXT_LENGTH", "12000"))
