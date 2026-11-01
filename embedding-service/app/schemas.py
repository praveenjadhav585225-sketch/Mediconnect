from pydantic import BaseModel, Field, ConfigDict

class EmbedRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    text: str = Field(min_length=10, max_length=12000)

class EmbedResponse(BaseModel):
    model: str
    dimensions: int
    embedding: list[float]
