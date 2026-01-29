"""
Recipe Agent - Generates full recipes
"""
from typing import Optional

from ..services.openai_client import openai_client
from ..schemas.agents import Suggestion, RecipeResult, NormalizedInput
from .prompts import RECIPE_AGENT_SYSTEM


class RecipeAgent:
    """
    Recipe Agent: Generate complete, cookable recipes for selected suggestions.
    """

    async def generate(
        self,
        suggestion: Suggestion,
        normalized_input: NormalizedInput,
        user_context: dict,
    ) -> RecipeResult:
        """
        Generate a full recipe for the selected suggestion.
        
        Args:
            suggestion: The selected suggestion
            normalized_input: Original normalized input
            user_context: Context bundle with profile, preferences, memories
            
        Returns:
            RecipeResult with complete recipe
        """
        # Build the prompt
        prompt_parts = [f"Generate a complete recipe for: {suggestion.title}"]
        
        prompt_parts.append(f"\n## Suggestion Details")
        prompt_parts.append(f"Summary: {suggestion.summary}")
        prompt_parts.append(f"Tags: {', '.join(suggestion.tags)}")
        prompt_parts.append(f"Target time: {suggestion.estimated_time_minutes} minutes")
        prompt_parts.append(f"Difficulty: {suggestion.difficulty}")
        if suggestion.health_rationale:
            prompt_parts.append(f"Health focus: {', '.join(suggestion.health_rationale)}")
        
        # Original input
        prompt_parts.append(f"\n## Original Input")
        if normalized_input.meal_name:
            prompt_parts.append(f"Based on meal: {normalized_input.meal_name}")
        if normalized_input.ingredients:
            prompt_parts.append(f"Using ingredients: {', '.join(normalized_input.ingredients)}")
        
        # User context
        prompt_parts.append(f"\n## User Profile (MUST RESPECT)")
        
        profile = user_context.get("profile", {})
        
        # Critical constraints
        if profile.get("allergies"):
            prompt_parts.append(f"⚠️ ALLERGIES (NEVER INCLUDE): {', '.join(profile['allergies'])}")
        if profile.get("dislikes"):
            prompt_parts.append(f"❌ Dislikes (avoid or substitute): {', '.join(profile['dislikes'])}")
        
        # Preferences
        if profile.get("diet_style"):
            prompt_parts.append(f"Diet: {profile['diet_style']}")
        if profile.get("cooking_skill"):
            prompt_parts.append(f"Skill level: {profile['cooking_skill']} (adapt complexity)")
        if profile.get("likes"):
            prompt_parts.append(f"Likes: {', '.join(profile['likes'])}")
        if profile.get("equipment"):
            prompt_parts.append(f"Available equipment: {', '.join(profile['equipment'])}")
        else:
            prompt_parts.append("Equipment: Standard kitchen (stovetop, oven, basic utensils)")
        if profile.get("household_size"):
            prompt_parts.append(f"Servings: {profile['household_size']}")
        if profile.get("goals"):
            prompt_parts.append(f"Health goals: {', '.join(profile['goals'])}")
        
        # Time constraint
        max_time = normalized_input.max_time_minutes or profile.get("time_per_meal_minutes")
        if max_time:
            prompt_parts.append(f"⏱️ Max cooking time: {max_time} minutes")
        
        prompt_parts.append("\nUnits: Metric (grams, ml, celsius)")
        prompt_parts.append("\nGenerate the complete recipe as JSON.")
        
        prompt = "\n".join(prompt_parts)
        
        try:
            messages = [
                {"role": "system", "content": RECIPE_AGENT_SYSTEM},
                {"role": "user", "content": prompt},
            ]
            
            result = await openai_client.chat_json(messages=messages, temperature=0.6)
            return RecipeResult.model_validate(result)
            
        except Exception as e:
            # Return a minimal error recipe
            return RecipeResult(
                name=suggestion.title,
                summary=f"Recipe generation failed: {str(e)}",
                ingredients=[],
                steps=["Recipe generation encountered an error. Please try again."],
                time_minutes=suggestion.estimated_time_minutes,
                difficulty=suggestion.difficulty,
                warnings=[f"Error: {str(e)}"]
            )
