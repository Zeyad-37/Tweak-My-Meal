"""
Vision Agent - Interprets food images
"""
from pathlib import Path
from typing import Optional

from ..services.openai_client import openai_client
from ..schemas.agents import VisionResult
from .prompts import VISION_AGENT_SYSTEM


class VisionAgent:
    """
    Vision Agent: Interpret images and classify as meal_photo, ingredients_photo, or unknown.
    Extract normalized entities (meal name, ingredients list).
    """

    async def analyze(
        self,
        image_paths: list[str | Path],
        user_text: Optional[str] = None,
        user_allergies: list[str] = None,
        user_dislikes: list[str] = None,
    ) -> VisionResult:
        """
        Analyze food images and return structured VisionResult.
        
        Args:
            image_paths: List of paths to images to analyze
            user_text: Optional accompanying text from user
            user_allergies: User's known allergies (to flag if detected)
            user_dislikes: User's known dislikes
            
        Returns:
            VisionResult with classification and extracted entities
        """
        # Build the prompt
        prompt_parts = ["Analyze this food image(s)."]
        
        if user_text:
            prompt_parts.append(f"\nUser's message: \"{user_text}\"")
        
        if user_allergies:
            prompt_parts.append(f"\nIMPORTANT - User has these allergies (flag if detected): {', '.join(user_allergies)}")
        
        if user_dislikes:
            prompt_parts.append(f"\nUser dislikes: {', '.join(user_dislikes)}")
        
        prompt_parts.append("\nProvide your analysis as JSON.")
        prompt = "\n".join(prompt_parts)
        
        try:
            # Call OpenAI Vision
            result = await openai_client.vision_json(
                prompt=prompt,
                image_paths=image_paths,
                system_prompt=VISION_AGENT_SYSTEM,
                temperature=0.3,  # Lower temp for more consistent classification
            )
            
            # Validate and return
            return VisionResult.model_validate(result)
            
        except Exception as e:
            # Return unknown with error in warnings
            return VisionResult(
                kind="unknown",
                confidence=0.0,
                warnings=[f"Vision analysis failed: {str(e)}"],
                follow_up_questions=["Could you describe what's in the image?"]
            )

    async def analyze_with_retry(
        self,
        image_paths: list[str | Path],
        user_text: Optional[str] = None,
        user_allergies: list[str] = None,
        user_dislikes: list[str] = None,
        max_retries: int = 1,
    ) -> VisionResult:
        """
        Analyze with retry on parse failure.
        """
        last_error = None
        
        for attempt in range(max_retries + 1):
            try:
                return await self.analyze(
                    image_paths=image_paths,
                    user_text=user_text,
                    user_allergies=user_allergies,
                    user_dislikes=user_dislikes,
                )
            except Exception as e:
                last_error = e
                if attempt < max_retries:
                    continue
        
        # All retries failed
        return VisionResult(
            kind="unknown",
            confidence=0.0,
            warnings=[f"Vision analysis failed after retries: {str(last_error)}"],
            follow_up_questions=["I had trouble analyzing the image. Could you describe what's in it?"]
        )
