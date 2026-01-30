"""
OpenAI Client Wrapper with Vision and Embedding support
"""
import json
import base64
import re
from typing import Optional, Any
from pathlib import Path
from openai import AsyncOpenAI

from ..config import settings


class OpenAIClient:
    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        self.text_model = settings.OPENAI_TEXT_MODEL
        self.vision_model = settings.OPENAI_VISION_MODEL
        self.embedding_model = settings.OPENAI_EMBEDDING_MODEL

    async def chat(
        self,
        messages: list[dict],
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 2048,
        response_format: Optional[dict] = None,
    ) -> str:
        """Send a chat completion request"""
        kwargs = {
            "model": model or self.text_model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if response_format:
            kwargs["response_format"] = response_format

        response = await self.client.chat.completions.create(**kwargs)
        return response.choices[0].message.content or ""

    async def chat_json(
        self,
        messages: list[dict],
        model: Optional[str] = None,
        temperature: float = 0.5,
        max_tokens: int = 2048,
    ) -> dict:
        """Chat completion expecting JSON response"""
        content = await self.chat(
            messages=messages,
            model=model,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format={"type": "json_object"},
        )
        # Clean potential markdown wrapping
        content = self._clean_json(content)
        return json.loads(content)

    async def vision(
        self,
        prompt: str,
        image_paths: list[str | Path],
        system_prompt: Optional[str] = None,
        temperature: float = 0.5,
        max_tokens: int = 2048,
    ) -> str:
        """Vision request with one or more images"""
        # Build content with images
        content: list[dict] = []
        
        # Add images first
        for img_path in image_paths:
            base64_image = self._encode_image(img_path)
            if base64_image:
                content.append({
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{base64_image}",
                        "detail": "high"
                    }
                })
        
        # Add text prompt
        content.append({"type": "text", "text": prompt})
        
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": content})
        
        response = await self.client.chat.completions.create(
            model=self.vision_model,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
        )
        return response.choices[0].message.content or ""

    async def vision_json(
        self,
        prompt: str,
        image_paths: list[str | Path],
        system_prompt: Optional[str] = None,
        temperature: float = 0.5,
        max_tokens: int = 2048,
    ) -> dict:
        """Vision request expecting JSON response"""
        # Add JSON instruction to prompt
        json_prompt = f"{prompt}\n\nRespond with valid JSON only, no markdown."
        content = await self.vision(
            prompt=json_prompt,
            image_paths=image_paths,
            system_prompt=system_prompt,
            temperature=temperature,
            max_tokens=max_tokens,
        )
        content = self._clean_json(content)
        return json.loads(content)

    async def generate_image(
        self,
        prompt: str,
        size: str = "1024x1024",
        quality: str = "standard",
    ) -> Optional[str]:
        """Generate an image using DALL-E and return the URL"""
        try:
            response = await self.client.images.generate(
                model="dall-e-3",
                prompt=prompt,
                size=size,
                quality=quality,
                n=1,
            )
            return response.data[0].url
        except Exception as e:
            print(f"Image generation failed: {e}")
            return None

    async def embed(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for texts"""
        response = await self.client.embeddings.create(
            model=self.embedding_model,
            input=texts,
        )
        return [item.embedding for item in response.data]

    async def embed_single(self, text: str) -> list[float]:
        """Generate embedding for a single text"""
        embeddings = await self.embed([text])
        return embeddings[0]

    def _encode_image(self, image_path: str | Path) -> Optional[str]:
        """Encode image to base64"""
        path = Path(image_path)
        if not path.exists():
            return None
        
        with open(path, "rb") as f:
            return base64.standard_b64encode(f.read()).decode("utf-8")

    def _clean_json(self, content: str) -> str:
        """Remove markdown code blocks if present"""
        content = content.strip()
        # Remove ```json ... ``` wrapper
        if content.startswith("```"):
            # Find the end of the first line (```json or ```)
            first_newline = content.find("\n")
            if first_newline != -1:
                content = content[first_newline + 1:]
            # Remove trailing ```
            if content.endswith("```"):
                content = content[:-3]
        return content.strip()


# Singleton instance
openai_client = OpenAIClient()
