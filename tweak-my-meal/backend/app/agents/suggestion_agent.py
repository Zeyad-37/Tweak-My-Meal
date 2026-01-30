"""
Suggestion Agent - Generates healthier meal options
"""
from typing import Optional
import uuid

from ..services.openai_client import openai_client
from ..schemas.agents import NormalizedInput, SuggestionsResult, Suggestion
from ..config import settings
from .prompts import SUGGESTION_AGENT_SYSTEM


class SuggestionAgent:
    """
    Suggestion Agent: Propose healthier meal options based on user input.
    """

    async def suggest(
        self,
        normalized_input: NormalizedInput,
        user_context: dict,
    ) -> SuggestionsResult:
        """
        Generate meal suggestions.
        
        Args:
            normalized_input: Normalized user input
            user_context: Context bundle with profile, preferences, memories
            
        Returns:
            SuggestionsResult with meal suggestions
        """
        # Determine suggestion count based on input type
        if normalized_input.input_kind in ["meal_photo", "text_meal"]:
            num_suggestions = settings.MEAL_SUGGESTION_COUNT
            task = "healthier variations of this meal"
        else:
            num_suggestions = settings.INGREDIENTS_SUGGESTION_COUNT
            task = "healthy meal ideas using these ingredients"
        
        # Build the prompt
        prompt_parts = [f"Generate {num_suggestions} {task}."]
        
        # Input details
        prompt_parts.append(f"\n## Input")
        prompt_parts.append(f"Type: {normalized_input.input_kind}")
        if normalized_input.meal_name:
            prompt_parts.append(f"Meal: {normalized_input.meal_name}")
        if normalized_input.ingredients:
            prompt_parts.append(f"Ingredients: {', '.join(normalized_input.ingredients)}")
        
        # User context
        prompt_parts.append(f"\n## User Context")
        
        profile = user_context.get("profile", {})
        if profile.get("diet_style"):
            prompt_parts.append(f"Diet: {profile['diet_style']}")
        if profile.get("cooking_skill"):
            prompt_parts.append(f"Skill: {profile['cooking_skill']}")
        if profile.get("allergies"):
            prompt_parts.append(f"ALLERGIES (MUST AVOID): {', '.join(profile['allergies'])}")
        if profile.get("dislikes"):
            prompt_parts.append(f"Dislikes (avoid): {', '.join(profile['dislikes'])}")
        if profile.get("likes"):
            prompt_parts.append(f"Likes: {', '.join(profile['likes'])}")
        if profile.get("equipment"):
            prompt_parts.append(f"Equipment: {', '.join(profile['equipment'])}")
        if profile.get("goals"):
            prompt_parts.append(f"Goals: {', '.join(profile['goals'])}")
        
        # Time constraint
        max_time = normalized_input.max_time_minutes or profile.get("time_per_meal_minutes")
        if max_time:
            prompt_parts.append(f"Max time: {max_time} minutes")
        
        # Preference facts
        pref_facts = user_context.get("preference_facts", [])
        if pref_facts:
            facts_str = ", ".join([f"{f['fact_key']}({f['strength']:.1f})" for f in pref_facts[:5]])
            prompt_parts.append(f"Learned preferences: {facts_str}")
        
        # Retrieved memories
        memories = user_context.get("memories", [])
        if memories:
            memories_str = "; ".join([m["text"] for m in memories[:3]])
            prompt_parts.append(f"Relevant memories: {memories_str}")
        
        # User modifications (added ingredients, etc)
        modification_request = user_context.get("modification_request")
        if modification_request:
            prompt_parts.append(f"\n## User Modification Request")
            prompt_parts.append(f"User wants to add/include: {modification_request}")
            prompt_parts.append("IMPORTANT: Incorporate these additions into all suggestions!")
        
        all_modifications = user_context.get("all_modifications", [])
        if all_modifications:
            prompt_parts.append(f"All requested additions: {', '.join(all_modifications)}")
        
        prompt_parts.append("\nGenerate suggestions as JSON.")
        prompt = "\n".join(prompt_parts)
        
        try:
            messages = [
                {"role": "system", "content": SUGGESTION_AGENT_SYSTEM},
                {"role": "user", "content": prompt},
            ]
            
            result = await openai_client.chat_json(messages=messages, temperature=0.7)
            
            # Ensure suggestion_ids are set
            suggestions = result.get("suggestions", [])
            for i, sug in enumerate(suggestions):
                if not sug.get("suggestion_id"):
                    sug["suggestion_id"] = f"sug_{i+1}"
            
            result["input_kind"] = normalized_input.input_kind
            return SuggestionsResult.model_validate(result)
            
        except Exception as e:
            # Return empty suggestions with error
            return SuggestionsResult(
                input_kind=normalized_input.input_kind,
                suggestions=[],
                follow_up_questions=[f"I had trouble generating suggestions. Could you provide more details?"]
            )
