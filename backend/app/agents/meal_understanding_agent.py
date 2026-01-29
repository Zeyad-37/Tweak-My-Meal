"""
Meal Understanding Agent - Normalizes input into structured format
"""
from typing import Optional

from ..services.openai_client import openai_client
from ..schemas.agents import VisionResult, NormalizedInput
from .prompts import MEAL_UNDERSTANDING_SYSTEM


class MealUnderstandingAgent:
    """
    Meal Understanding Agent: Normalize user input (text and/or vision results)
    into a common internal representation.
    """

    async def normalize(
        self,
        text: Optional[str] = None,
        vision_result: Optional[VisionResult] = None,
        previous_answers: Optional[dict] = None,
    ) -> NormalizedInput:
        """
        Normalize input into structured format.
        
        Args:
            text: User's text input
            vision_result: Result from Vision Agent (if images were provided)
            previous_answers: Answers to previous follow-up questions
            
        Returns:
            NormalizedInput with classification and extracted entities
        """
        # Build context for the agent
        context_parts = []
        
        if vision_result:
            context_parts.append(f"Vision Analysis Result:")
            context_parts.append(f"- Kind: {vision_result.kind}")
            context_parts.append(f"- Confidence: {vision_result.confidence}")
            if vision_result.detected.meal_name:
                context_parts.append(f"- Detected meal: {vision_result.detected.meal_name}")
            if vision_result.detected.ingredients:
                ingredients = [f"{i.name} ({i.quantity_hint})" if i.quantity_hint else i.name 
                              for i in vision_result.detected.ingredients]
                context_parts.append(f"- Detected ingredients: {', '.join(ingredients)}")
            if vision_result.detected.cuisine_hint:
                context_parts.append(f"- Cuisine hint: {vision_result.detected.cuisine_hint}")
        
        if text:
            context_parts.append(f"\nUser's text: \"{text}\"")
        
        if previous_answers:
            context_parts.append(f"\nPrevious Q&A:")
            for q, a in previous_answers.items():
                context_parts.append(f"  Q: {q}")
                context_parts.append(f"  A: {a}")
        
        context_parts.append("\nNormalize this input into the structured format.")
        
        prompt = "\n".join(context_parts)
        
        try:
            messages = [
                {"role": "system", "content": MEAL_UNDERSTANDING_SYSTEM},
                {"role": "user", "content": prompt},
            ]
            
            result = await openai_client.chat_json(messages=messages, temperature=0.3)
            return NormalizedInput.model_validate(result)
            
        except Exception as e:
            # Fallback: try to infer from available data
            return self._fallback_normalize(text, vision_result, str(e))

    def _fallback_normalize(
        self,
        text: Optional[str],
        vision_result: Optional[VisionResult],
        error: str,
    ) -> NormalizedInput:
        """Fallback normalization using heuristics"""
        
        # If we have vision result, use that
        if vision_result and vision_result.kind != "unknown":
            ingredients = [i.name for i in vision_result.detected.ingredients]
            return NormalizedInput(
                input_kind=vision_result.kind,
                meal_name=vision_result.detected.meal_name,
                ingredients=ingredients,
                missing_info_questions=vision_result.follow_up_questions,
            )
        
        # Try to infer from text
        if text:
            text_lower = text.lower()
            
            # Check for ingredient-like patterns
            ingredient_keywords = ["i have", "using", "ingredients", "with these", "what can i make"]
            is_ingredients = any(kw in text_lower for kw in ingredient_keywords)
            
            if is_ingredients:
                return NormalizedInput(
                    input_kind="text_ingredients",
                    ingredients=[text],  # Let suggestion agent parse
                    missing_info_questions=[],
                )
            else:
                return NormalizedInput(
                    input_kind="text_meal",
                    meal_name=text,
                    missing_info_questions=[],
                )
        
        # Unknown
        return NormalizedInput(
            input_kind="unknown",
            missing_info_questions=["Could you tell me more about what you'd like help with?"],
        )
