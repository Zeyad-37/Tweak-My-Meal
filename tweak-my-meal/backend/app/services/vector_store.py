"""
Simple In-Memory Vector Store for Memory Retrieval
Uses OpenAI embeddings with cosine similarity search
"""
import json
import math
from pathlib import Path
from typing import Optional

from ..config import settings
from .openai_client import openai_client


def cosine_similarity(a: list[float], b: list[float]) -> float:
    """Calculate cosine similarity between two vectors"""
    dot_product = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot_product / (norm_a * norm_b)


class VectorStore:
    """Simple file-backed vector store with OpenAI embeddings"""
    
    def __init__(self, user_id: str):
        self.user_id = user_id
        self.persist_dir = settings.user_vector_dir(user_id)
        self.persist_dir.mkdir(parents=True, exist_ok=True)
        self._index_file = self.persist_dir / "index.json"
        self._memories: dict[str, dict] = {}  # memory_id -> {text, embedding, metadata}
        self._load()

    def _load(self):
        """Load index from disk"""
        if self._index_file.exists():
            try:
                with open(self._index_file, "r") as f:
                    self._memories = json.load(f)
            except Exception:
                self._memories = {}

    def _save(self):
        """Save index to disk"""
        try:
            with open(self._index_file, "w") as f:
                json.dump(self._memories, f)
        except Exception:
            pass

    async def add_memory(
        self,
        memory_id: str,
        text: str,
        metadata: Optional[dict] = None,
    ) -> str:
        """Add a memory item with its embedding"""
        try:
            # Generate embedding via OpenAI
            embedding = await openai_client.embed_single(text)
            
            self._memories[memory_id] = {
                "text": text,
                "embedding": embedding,
                "metadata": metadata or {},
            }
            self._save()
        except Exception as e:
            print(f"Warning: Failed to add memory: {e}")
        
        return memory_id

    async def search(
        self,
        query: str,
        top_k: int = 5,
        filter_metadata: Optional[dict] = None,
    ) -> list[dict]:
        """Search for similar memories using cosine similarity"""
        if not self._memories:
            return []
        
        try:
            # Generate query embedding
            query_embedding = await openai_client.embed_single(query)
            
            # Calculate similarities
            scored = []
            for memory_id, data in self._memories.items():
                # Apply metadata filter if provided
                if filter_metadata:
                    match = all(
                        data.get("metadata", {}).get(k) == v 
                        for k, v in filter_metadata.items()
                    )
                    if not match:
                        continue
                
                similarity = cosine_similarity(query_embedding, data["embedding"])
                scored.append((memory_id, data, similarity))
            
            # Sort by similarity (descending) and take top_k
            scored.sort(key=lambda x: x[2], reverse=True)
            
            return [
                {
                    "memory_id": memory_id,
                    "text": data["text"],
                    "metadata": data.get("metadata", {}),
                    "distance": 1 - similarity,  # Convert to distance
                }
                for memory_id, data, similarity in scored[:top_k]
            ]
        except Exception as e:
            print(f"Warning: Vector search failed: {e}")
            return []

    def delete_memory(self, memory_id: str):
        """Delete a memory item"""
        if memory_id in self._memories:
            del self._memories[memory_id]
            self._save()

    def persist(self):
        """Persist to disk"""
        self._save()


# Cache of vector store instances per user
_vector_stores: dict[str, VectorStore] = {}


def get_vector_store(user_id: str) -> VectorStore:
    """Get or create vector store for user"""
    if user_id not in _vector_stores:
        _vector_stores[user_id] = VectorStore(user_id)
    return _vector_stores[user_id]
