"""
Orchestrator - Deterministic coordinator for agent pipeline
"""
import json
import uuid
from pathlib import Path
from typing import Optional, Union
import shutil

from ..config import settings
from ..db import get_db
from ..schemas.api import (
    FollowUpResponse, SuggestionsResponse, RecipeResponse,
    SourceInfo, Suggestion as ApiSuggestion
)
from ..schemas.agents import VisionResult, NormalizedInput, Suggestion, RecipeResult
from ..agents import (
    VisionAgent, MealUnderstandingAgent, SuggestionAgent,
    RecipeAgent, MemoryUpdateAgent
)
from .vector_store import get_vector_store


class Orchestrator:
    """
    Orchestrator (Coach): Deterministic code that coordinates the agent pipeline.
    
    Responsibilities:
    - Maintains session state
    - Builds user context (profile + facts + memories)
    - Calls LLM agents in sequence
    - Validates outputs
    - Persists data
    """

    def __init__(self, user_id: str):
        self.user_id = user_id
        self.vision_agent = VisionAgent()
        self.meal_understanding_agent = MealUnderstandingAgent()
        self.suggestion_agent = SuggestionAgent()
        self.recipe_agent = RecipeAgent()
        self.memory_update_agent = MemoryUpdateAgent()

    async def _get_db(self):
        return await get_db(self.user_id)

    def _get_vector_store(self):
        return get_vector_store(self.user_id)

    async def build_user_context(self, query_text: Optional[str] = None) -> dict:
        """Build context bundle for agents"""
        db = await self._get_db()
        
        # Get profile
        profile = await db.get_profile(self.user_id) or {}
        
        # Get top preference facts
        preference_facts = await db.get_top_preference_facts(
            self.user_id, 
            limit=settings.TOP_K_PREFERENCE_FACTS
        )
        
        # Get recent meals
        recent_meals = await db.get_recent_meals(
            self.user_id,
            limit=settings.RECENT_MEALS_COUNT
        )
        
        # Retrieve relevant memories via vector search
        memories = []
        if query_text:
            try:
                vs = self._get_vector_store()
                memories = await vs.search(query_text, top_k=settings.TOP_K_MEMORIES)
            except Exception:
                pass  # Vector store may not have data yet
        
        return {
            "profile": profile,
            "preference_facts": preference_facts,
            "recent_meals": recent_meals,
            "memories": memories,
        }

    async def save_uploaded_images(self, images: list[tuple[str, bytes]]) -> list[str]:
        """Save uploaded images and return paths"""
        images_dir = settings.user_images_dir(self.user_id)
        images_dir.mkdir(parents=True, exist_ok=True)
        
        saved_paths = []
        for filename, content in images:
            # Generate unique filename
            ext = Path(filename).suffix or ".jpg"
            new_filename = f"{uuid.uuid4()}{ext}"
            path = images_dir / new_filename
            
            with open(path, "wb") as f:
                f.write(content)
            
            saved_paths.append(str(path))
        
        return saved_paths

    async def process_chat_turn(
        self,
        session_id: str,
        text: Optional[str] = None,
        image_paths: list[str] = None,
        mode_hint: str = "auto",
        client_context: Optional[dict] = None,
    ) -> Union[FollowUpResponse, SuggestionsResponse]:
        """
        Process a chat turn through the agent pipeline.
        
        Returns either follow-up questions or suggestions.
        """
        db = await self._get_db()
        
        # Check for existing session state (pending follow-ups)
        existing_state = await db.get_session_state(session_id)
        
        # Build user context
        user_context = await self.build_user_context(text)
        profile = user_context.get("profile", {})
        
        # Apply client context overrides
        if client_context and client_context.get("max_time_minutes"):
            # Store for later use
            pass
        
        vision_result: Optional[VisionResult] = None
        
        # Step 1: Vision Agent (if images provided)
        if image_paths:
            vision_result = await self.vision_agent.analyze_with_retry(
                image_paths=image_paths,
                user_text=text,
                user_allergies=profile.get("allergies", []),
                user_dislikes=profile.get("dislikes", []),
            )
            
            # If vision is uncertain and has follow-up questions, ask them
            if vision_result.kind == "unknown" and vision_result.follow_up_questions:
                # Save state
                await db.upsert_session_state(session_id, self.user_id, {
                    "step": "awaiting_followup",
                    "vision_result": vision_result.model_dump(),
                    "image_paths": image_paths,
                    "original_text": text,
                })
                
                return FollowUpResponse(
                    session_id=session_id,
                    questions=vision_result.follow_up_questions,
                    blocking=True,
                )
        
        # Step 2: Meal Understanding Agent
        previous_answers = None
        if existing_state and existing_state.get("step") == "awaiting_followup":
            # User is answering follow-up questions
            previous_answers = {"follow_up": text}
            if existing_state.get("vision_result"):
                vision_result = VisionResult.model_validate(existing_state["vision_result"])
        
        normalized = await self.meal_understanding_agent.normalize(
            text=text,
            vision_result=vision_result,
            previous_answers=previous_answers,
        )
        
        # If normalization needs more info
        if normalized.input_kind == "unknown" and normalized.missing_info_questions:
            await db.upsert_session_state(session_id, self.user_id, {
                "step": "awaiting_followup",
                "vision_result": vision_result.model_dump() if vision_result else None,
                "image_paths": image_paths,
            })
            
            return FollowUpResponse(
                session_id=session_id,
                questions=normalized.missing_info_questions,
                blocking=True,
            )
        
        # Apply time constraint from client context
        if client_context and client_context.get("max_time_minutes"):
            normalized.max_time_minutes = client_context["max_time_minutes"]
        
        # Step 3: Suggestion Agent
        suggestions_result = await self.suggestion_agent.suggest(
            normalized_input=normalized,
            user_context=user_context,
        )
        
        # If suggestions need follow-up
        if not suggestions_result.suggestions and suggestions_result.follow_up_questions:
            return FollowUpResponse(
                session_id=session_id,
                questions=suggestions_result.follow_up_questions,
                blocking=True,
            )
        
        # Save session state with suggestions
        await db.upsert_session_state(session_id, self.user_id, {
            "step": "awaiting_selection",
            "last_input_kind": normalized.input_kind,
            "vision_result": vision_result.model_dump() if vision_result else None,
            "normalized_input": normalized.model_dump(),
            "suggestions": [s.model_dump() for s in suggestions_result.suggestions],
            "image_paths": image_paths,
            "original_text": text,
        })
        
        # Return suggestions
        return SuggestionsResponse(
            session_id=session_id,
            source=SourceInfo(
                input_kind=normalized.input_kind,
                vision_result=vision_result,
            ),
            suggestions=[
                ApiSuggestion(
                    suggestion_id=s.suggestion_id,
                    title=s.title,
                    summary=s.summary,
                    health_rationale=s.health_rationale,
                    tags=s.tags,
                    estimated_time_minutes=s.estimated_time_minutes,
                    difficulty=s.difficulty,
                )
                for s in suggestions_result.suggestions
            ],
        )

    async def process_selection(
        self,
        session_id: str,
        suggestion_id: str,
    ) -> RecipeResponse:
        """
        Process user's selection of a suggestion and generate recipe.
        """
        db = await self._get_db()
        
        # Get session state
        state = await db.get_session_state(session_id)
        if not state:
            raise ValueError("Session not found")
        
        if state.get("step") != "awaiting_selection":
            raise ValueError("No pending selection")
        
        # Find the selected suggestion
        suggestions = state.get("suggestions", [])
        selected = None
        for s in suggestions:
            if s.get("suggestion_id") == suggestion_id:
                selected = Suggestion.model_validate(s)
                break
        
        if not selected:
            raise ValueError(f"Suggestion {suggestion_id} not found in session")
        
        # Get normalized input
        normalized = NormalizedInput.model_validate(state.get("normalized_input", {}))
        
        # Build context
        user_context = await self.build_user_context(selected.title)
        
        # Step 4: Recipe Agent
        recipe = await self.recipe_agent.generate(
            suggestion=selected,
            normalized_input=normalized,
            user_context=user_context,
        )
        
        # Generate meal ID
        meal_id = str(uuid.uuid4())
        
        # Persist meal
        await db.create_meal(
            meal_id=meal_id,
            user_id=self.user_id,
            title=recipe.name,
            source_kind=normalized.input_kind,
            recipe_json=recipe.model_dump_json(),
            tags=selected.tags,
            input_text=state.get("original_text"),
            input_image_paths=state.get("image_paths"),
            vision_result_json=json.dumps(state.get("vision_result")) if state.get("vision_result") else None,
            suggestion_id=suggestion_id,
        )
        
        # Update session state
        await db.upsert_session_state(session_id, self.user_id, {
            "step": "done",
            "meal_id": meal_id,
        })
        
        return RecipeResponse(
            session_id=session_id,
            meal_id=meal_id,
            recipe=recipe,
        )

    async def process_feedback(
        self,
        meal_id: str,
        liked: bool,
        cooked_again: bool,
        tags: list[str],
        notes: Optional[str],
    ) -> dict:
        """
        Process feedback and trigger learning.
        """
        db = await self._get_db()
        
        # Get meal
        meal = await db.get_meal(meal_id)
        if not meal:
            raise ValueError(f"Meal {meal_id} not found")
        
        # Save outcome
        await db.create_outcome(
            meal_id=meal_id,
            user_id=self.user_id,
            liked=liked,
            cooked_again=cooked_again,
            tags=tags,
            notes=notes,
        )
        
        # Get current preferences for context
        preference_facts = await db.get_top_preference_facts(
            self.user_id,
            limit=settings.TOP_K_PREFERENCE_FACTS
        )
        
        profile = await db.get_profile(self.user_id)
        
        # Step 5: Memory Update Agent
        memory_result = await self.memory_update_agent.process_feedback(
            meal_title=meal["title"],
            recipe_tags=meal.get("tags", []),
            liked=liked,
            cooked_again=cooked_again,
            feedback_tags=tags,
            notes=notes,
            current_preference_facts=preference_facts,
            user_profile=profile,
        )
        
        # Persist memory items
        vs = self._get_vector_store()
        for item in memory_result.memory_items:
            memory_id = str(uuid.uuid4())
            await db.create_memory_item(
                memory_id=memory_id,
                user_id=self.user_id,
                kind=item.kind,
                text=item.text,
                salience=item.salience,
                source_meal_id=meal_id,
                embedding_id=memory_id,
            )
            # Add to vector store
            try:
                await vs.add_memory(
                    memory_id=memory_id,
                    text=item.text,
                    metadata={"kind": item.kind, "meal_id": meal_id},
                )
            except Exception:
                pass  # Vector store may fail, continue
        
        # Update preference facts
        for fact in memory_result.preference_facts:
            await db.update_preference_fact(
                user_id=self.user_id,
                fact_key=fact.fact_key,
                delta=fact.delta_strength,
                source_meal_id=meal_id,
            )
        
        # Apply profile patch
        if profile and (memory_result.profile_patch.likes_add or 
                       memory_result.profile_patch.dislikes_add):
            current_likes = profile.get("likes", [])
            current_dislikes = profile.get("dislikes", [])
            
            new_likes = list(set(current_likes + memory_result.profile_patch.likes_add))
            new_dislikes = list(set(current_dislikes + memory_result.profile_patch.dislikes_add))
            
            profile["likes"] = new_likes
            profile["dislikes"] = new_dislikes
            
            await db.upsert_profile(self.user_id, profile)
        
        # Generate updated summary
        updated_profile = await db.get_profile(self.user_id)
        summary = self._generate_profile_summary(updated_profile)
        
        return {
            "updated_profile_summary": summary,
            "memory_items_written": len(memory_result.memory_items),
            "preference_facts_updated": len(memory_result.preference_facts),
        }

    def _generate_profile_summary(self, profile: Optional[dict]) -> str:
        """Generate a human-readable profile summary"""
        if not profile:
            return "New user - no profile yet"
        
        parts = []
        if profile.get("display_name"):
            parts.append(profile["display_name"])
        if profile.get("diet_style"):
            parts.append(profile["diet_style"])
        if profile.get("cooking_skill"):
            parts.append(f"{profile['cooking_skill']} cook")
        if profile.get("goals"):
            parts.append(f"Goals: {', '.join(profile['goals'][:2])}")
        
        return " | ".join(parts) if parts else "Basic profile"
