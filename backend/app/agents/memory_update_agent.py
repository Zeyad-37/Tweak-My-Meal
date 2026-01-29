"""
Memory Update Agent - Learns from user feedback
"""
from typing import Optional

from ..services.openai_client import openai_client
from ..schemas.agents import MemoryWriteResult, RecipeResult
from .prompts import MEMORY_UPDATE_SYSTEM


class MemoryUpdateAgent:
    """
    Memory Update Agent: Learn from feedback and generate memory items,
    preference facts, and profile patches.
    """

    async def process_feedback(
        self,
        meal_title: str,
        recipe_tags: list[str],
        liked: bool,
        cooked_again: bool,
        feedback_tags: list[str],
        notes: Optional[str],
        current_preference_facts: list[dict],
        user_profile: Optional[dict] = None,
    ) -> MemoryWriteResult:
        """
        Process feedback and generate learning outputs.
        
        Args:
            meal_title: Title of the meal
            recipe_tags: Tags from the recipe
            liked: Whether user liked it
            cooked_again: Whether user would cook again
            feedback_tags: Tags user added (e.g., "too_spicy", "easy")
            notes: User's notes
            current_preference_facts: Current top preference facts
            user_profile: User's profile for context
            
        Returns:
            MemoryWriteResult with items to persist
        """
        # Build the prompt
        prompt_parts = ["Process this meal feedback and generate learning outputs."]
        
        prompt_parts.append(f"\n## Meal")
        prompt_parts.append(f"Title: {meal_title}")
        prompt_parts.append(f"Tags: {', '.join(recipe_tags)}")
        
        prompt_parts.append(f"\n## Feedback")
        prompt_parts.append(f"Liked: {'Yes' if liked else 'No'}")
        prompt_parts.append(f"Would cook again: {'Yes' if cooked_again else 'No'}")
        if feedback_tags:
            prompt_parts.append(f"User tags: {', '.join(feedback_tags)}")
        if notes:
            prompt_parts.append(f"User notes: \"{notes}\"")
        
        prompt_parts.append(f"\n## Current Preferences")
        if current_preference_facts:
            for fact in current_preference_facts[:10]:
                prompt_parts.append(f"- {fact['fact_key']}: {fact['strength']:.1f}")
        else:
            prompt_parts.append("No preferences learned yet.")
        
        if user_profile:
            prompt_parts.append(f"\n## User Profile Context")
            if user_profile.get("diet_style"):
                prompt_parts.append(f"Diet: {user_profile['diet_style']}")
            if user_profile.get("goals"):
                prompt_parts.append(f"Goals: {', '.join(user_profile['goals'])}")
        
        prompt_parts.append("\n## Instructions")
        if liked:
            prompt_parts.append("- User LIKED this meal. Strengthen positive patterns.")
            if cooked_again:
                prompt_parts.append("- User would COOK AGAIN. This is a strong positive signal!")
        else:
            prompt_parts.append("- User DISLIKED this meal. Create avoidance facts.")
        
        prompt_parts.append("- Extract any explicit preferences from notes")
        prompt_parts.append("- Generate memory items, preference fact deltas, and profile patches")
        prompt_parts.append("\nGenerate learning outputs as JSON.")
        
        prompt = "\n".join(prompt_parts)
        
        try:
            messages = [
                {"role": "system", "content": MEMORY_UPDATE_SYSTEM},
                {"role": "user", "content": prompt},
            ]
            
            result = await openai_client.chat_json(messages=messages, temperature=0.5)
            return MemoryWriteResult.model_validate(result)
            
        except Exception as e:
            # Return minimal learning on error
            return self._fallback_learning(
                meal_title, recipe_tags, liked, cooked_again, feedback_tags, notes
            )

    def _fallback_learning(
        self,
        meal_title: str,
        recipe_tags: list[str],
        liked: bool,
        cooked_again: bool,
        feedback_tags: list[str],
        notes: Optional[str],
    ) -> MemoryWriteResult:
        """Generate basic learning without LLM"""
        from ..schemas.agents import MemoryItem, PreferenceFact, ProfilePatch
        
        memory_items = []
        preference_facts = []
        profile_patch = ProfilePatch()
        
        # Base strength
        strength = 0.3 if liked else -0.3
        if cooked_again:
            strength = 0.5
        
        # Create memory item
        outcome = "liked" if liked else "disliked"
        memory_items.append(MemoryItem(
            text=f"User {outcome} {meal_title}",
            kind="like" if liked else "dislike",
            salience=abs(strength),
        ))
        
        # Create preference facts from tags
        for tag in recipe_tags[:5]:
            fact_key = f"{'likes' if liked else 'avoid'}:{tag.lower().replace(' ', '_')}"
            preference_facts.append(PreferenceFact(
                fact_key=fact_key,
                delta_strength=strength,
                reason=f"From {outcome} meal: {meal_title}",
            ))
        
        # Process feedback tags
        for tag in feedback_tags:
            tag_lower = tag.lower()
            if tag_lower in ["too_spicy", "too_hot"]:
                preference_facts.append(PreferenceFact(
                    fact_key="avoid:very_spicy",
                    delta_strength=0.3,
                    reason=f"User found {meal_title} too spicy",
                ))
            elif tag_lower in ["easy", "simple"]:
                preference_facts.append(PreferenceFact(
                    fact_key="likes:easy_recipes",
                    delta_strength=0.2,
                    reason=f"User appreciated ease of {meal_title}",
                ))
        
        return MemoryWriteResult(
            memory_items=memory_items,
            preference_facts=preference_facts,
            profile_patch=profile_patch,
        )
