"""
Journal API Routes - Weekly check-ins and wisdom
"""
from datetime import datetime, timezone, timedelta
from typing import Optional
from fastapi import APIRouter
from pydantic import BaseModel

from ..schemas.api import ApiResponse
from ..db import get_db
from ..services.openai_client import openai_client

router = APIRouter(prefix="/api/journal", tags=["journal"])


class AddReflectionRequest(BaseModel):
    user_id: str = "user_0001"
    text: str


@router.get("/weekly", response_model=ApiResponse)
async def get_weekly_journal(user_id: str = "user_0001"):
    """
    Get weekly journal data including reflections, AI wisdom, and meal history.
    """
    try:
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        # Get current week boundaries
        today = datetime.now(timezone.utc)
        start_of_week = today - timedelta(days=today.weekday())
        start_of_week = start_of_week.replace(hour=0, minute=0, second=0, microsecond=0)
        
        # Get reflections for this week
        reflections = await _get_week_reflections(db, user_id, start_of_week)
        
        # Get meals for this week (with full details)
        meals = await _get_week_meals(db, user_id, start_of_week)
        
        # Get user profile for context
        profile = await db.get_profile(user_id)
        
        # Generate weekly wisdom
        wisdom = await _generate_weekly_wisdom(profile, meals, reflections, start_of_week)
        
        # Generate better bite tips for each meal
        meals_with_tips = await _enrich_meals_with_tips(meals)
        
        return ApiResponse.success({
            "week_of": start_of_week.strftime("%b %d").upper(),
            "reflections": reflections,
            "reflection_count": len(reflections),
            "meals_this_week": len(meals),
            "meals": meals_with_tips,
            "wisdom": wisdom,
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


@router.post("/reflection", response_model=ApiResponse)
async def add_reflection(request: AddReflectionRequest):
    """
    Add a new weekly reflection/check-in.
    """
    try:
        db = await get_db(request.user_id)
        await db.ensure_user(request.user_id)
        
        # Save reflection using session state
        reflection_id = await _save_reflection_as_memory(db, request.user_id, request.text)
        
        return ApiResponse.success({
            "reflection_id": reflection_id,
            "saved": True,
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


@router.get("/reflections", response_model=ApiResponse)
async def get_reflections(user_id: str = "user_0001", limit: int = 10):
    """
    Get recent reflections.
    """
    try:
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        today = datetime.now(timezone.utc)
        start_of_week = today - timedelta(days=today.weekday())
        start_of_week = start_of_week.replace(hour=0, minute=0, second=0, microsecond=0)
        
        reflections = await _get_week_reflections(db, user_id, start_of_week)
        
        return ApiResponse.success({
            "reflections": reflections[:limit],
            "total": len(reflections),
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


async def _get_week_reflections(db, user_id: str, start_of_week: datetime) -> list[dict]:
    """Get reflections for the current week."""
    # Get from session state where we store reflections
    state = await db.get_session_state(f"reflections_{user_id}")
    if not state:
        return []
    
    reflections = state.get("items", [])
    
    # Filter to this week
    week_reflections = []
    for r in reflections:
        try:
            created = datetime.fromisoformat(r["created_at"].replace("Z", "+00:00"))
            if created >= start_of_week:
                week_reflections.append(r)
        except:
            pass
    
    return week_reflections


async def _get_week_meals(db, user_id: str, start_of_week: datetime) -> list[dict]:
    """Get meals for the current week."""
    all_meals = await db.get_history(user_id, limit=100, offset=0)
    
    week_meals = []
    for meal in all_meals:
        try:
            created = datetime.fromisoformat(meal["created_at"].replace("Z", "+00:00"))
            if created >= start_of_week:
                # Convert local image path to URL
                if meal.get("image_path"):
                    from pathlib import Path
                    filename = Path(meal["image_path"]).name
                    meal["image_url"] = f"http://127.0.0.1:8080/images/{user_id}/{filename}"
                week_meals.append(meal)
        except:
            pass
    
    return week_meals


async def _save_reflection_as_memory(db, user_id: str, text: str) -> str:
    """Save reflection to session state."""
    import uuid
    
    state = await db.get_session_state(f"reflections_{user_id}")
    items = state.get("items", []) if state else []
    
    reflection_id = str(uuid.uuid4())
    items.append({
        "id": reflection_id,
        "text": text,
        "created_at": datetime.now(timezone.utc).isoformat(),
    })
    
    # Keep last 50 reflections
    items = items[-50:]
    
    await db.upsert_session_state(f"reflections_{user_id}", user_id, {
        "items": items,
    })
    
    return reflection_id


async def _enrich_meals_with_tips(meals: list[dict]) -> list[dict]:
    """Add better bite tips and science to each meal."""
    enriched = []
    
    for meal in meals:
        title = meal.get("title", "Meal")
        
        # Generate better bite tip
        try:
            tip_prompt = f"""For the meal "{title}", provide:
1. "better_bite": A specific, actionable tip to make this meal healthier (1-2 sentences)
2. "the_science": A brief explanation of why this tip works nutritionally (1-2 sentences)

Respond as JSON with "better_bite" and "the_science" keys. No emojis."""
            
            messages = [
                {"role": "system", "content": "You are a nutrition expert. Give practical, science-backed advice."},
                {"role": "user", "content": tip_prompt},
            ]
            
            result = await openai_client.chat_json(messages=messages, temperature=0.7)
            
            meal["better_bite"] = result.get("better_bite", "Add more vegetables to boost fiber and nutrients.")
            meal["the_science"] = result.get("the_science", "Fiber helps with digestion and keeps you feeling full longer.")
        except:
            meal["better_bite"] = "Add a palm-sized serving of protein to feel fuller and lighter longer."
            meal["the_science"] = "Protein slows gastric emptying and stabilizes blood sugar, reducing hunger swings."
        
        enriched.append(meal)
    
    return enriched


async def _generate_weekly_wisdom(
    profile: dict | None,
    meals: list[dict],
    reflections: list[dict],
    start_of_week: datetime,
) -> dict:
    """Generate AI weekly wisdom based on user's week."""
    try:
        # Build context
        context_parts = ["Generate weekly wisdom for a nutrition app user."]
        
        if profile:
            if profile.get("goals"):
                context_parts.append(f"User goals: {', '.join(profile['goals'])}")
            if profile.get("diet_style"):
                context_parts.append(f"Diet: {profile['diet_style']}")
        
        if meals:
            meal_titles = [m.get("title", "meal") for m in meals[:10]]
            context_parts.append(f"Meals this week: {', '.join(meal_titles)}")
        else:
            context_parts.append("No meals logged this week yet.")
        
        if reflections:
            reflection_texts = [r.get("text", "") for r in reflections[:5]]
            context_parts.append(f"User reflections: {'; '.join(reflection_texts)}")
        
        context_parts.append("""
Generate a response as JSON with:
1. "summary": A warm, encouraging 1-2 sentence summary of their week (acknowledge their reflections if any)
2. "tips": Array of exactly 4 actionable tips for the coming week. Each tip should be specific and achievable.

Keep tips concise (1-2 sentences each). Be encouraging but realistic. No emojis.""")
        
        messages = [
            {"role": "system", "content": "You are a supportive nutrition coach. Give personalized, actionable advice."},
            {"role": "user", "content": "\n".join(context_parts)},
        ]
        
        result = await openai_client.chat_json(messages=messages, temperature=0.7)
        
        return {
            "summary": result.get("summary", "Keep up the great work on your nutrition journey!"),
            "tips": result.get("tips", [
                "Add a serving of vegetables to one meal today",
                "Drink a glass of water before each meal",
                "Try a new healthy recipe this week",
                "Take a moment to enjoy your food mindfully",
            ]),
        }
        
    except Exception as e:
        # Fallback wisdom
        return {
            "summary": "Every meal is a chance to nourish yourself. Keep making mindful choices!",
            "tips": [
                "Add a handful of leafy greens like spinach or kale to one meal each day",
                "Try drinking a full glass of water 10 minutes before your next meal",
                "Experiment with one new healthy ingredient this week",
                "Set a gentle reminder to pause and take 3 breaths before eating",
            ],
        }
