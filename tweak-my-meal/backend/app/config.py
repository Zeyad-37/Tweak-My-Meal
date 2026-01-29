import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env from project root
env_path = Path(__file__).parent.parent.parent / ".env"
load_dotenv(env_path)


class Settings:
    # API Keys
    OPENAI_API_KEY: str = os.getenv("OPEN_AI_KEY", "")
    
    # OpenAI Models
    OPENAI_TEXT_MODEL: str = "gpt-4o"
    OPENAI_VISION_MODEL: str = "gpt-4o"
    OPENAI_EMBEDDING_MODEL: str = "text-embedding-3-small"
    
    # Storage paths
    DATA_ROOT: Path = Path(__file__).parent.parent.parent / "local_data"
    DEFAULT_USER_ID: str = "user_0001"
    
    # Server
    HOST: str = "127.0.0.1"
    PORT: int = 8080
    
    # Defaults
    TOP_K_MEMORIES: int = 5
    TOP_K_PREFERENCE_FACTS: int = 10
    RECENT_MEALS_COUNT: int = 5
    SESSION_TTL_HOURS: int = 24
    
    # Suggestion counts
    MEAL_SUGGESTION_COUNT: int = 3
    INGREDIENTS_SUGGESTION_COUNT: int = 5

    @classmethod
    def user_storage_root(cls, user_id: str) -> Path:
        return cls.DATA_ROOT / user_id

    @classmethod
    def user_images_dir(cls, user_id: str) -> Path:
        return cls.user_storage_root(user_id) / "images"

    @classmethod
    def user_db_path(cls, user_id: str) -> Path:
        return cls.user_storage_root(user_id) / "sqlite" / "app.db"

    @classmethod
    def user_vector_dir(cls, user_id: str) -> Path:
        return cls.user_storage_root(user_id) / "vector"


settings = Settings()
