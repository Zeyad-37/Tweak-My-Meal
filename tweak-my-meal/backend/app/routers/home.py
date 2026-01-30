"""
Home Screen API Routes - Daily tip, today's meals, suggested bites, etc.
"""
from datetime import datetime, timezone
from fastapi import APIRouter
import uuid
import asyncio
import httpx
from pathlib import Path

from ..schemas.api import ApiResponse
from ..db import get_db
from ..services.openai_client import openai_client
from ..config import settings

router = APIRouter(prefix="/api/home", tags=["home"])


# Cache for suggested meals (per user per day)
_suggested_meals_cache: dict[str, dict] = {}
# Cache for suggested bite images (suggestion_id -> image_url)
_suggested_images_cache: dict[str, str] = {}
# Track ongoing image generation tasks
_image_generation_tasks: dict[str, bool] = {}


@router.get("/daily-tip", response_model=ApiResponse)
async def get_daily_tip(user_id: str = "user_0001"):
    """
    Get AI-generated daily tip personalized to user profile.
    """
    try:
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        # Get user profile for personalization
        profile = await db.get_profile(user_id)
        pref_facts = await db.get_top_preference_facts(user_id, limit=5)
        
        # Build context for tip generation
        context_parts = ["Generate a short, helpful nutrition tip (1-2 sentences max)."]
        
        if profile:
            if profile.get("goals"):
                context_parts.append(f"User goals: {', '.join(profile['goals'])}")
            if profile.get("diet_style"):
                context_parts.append(f"Diet style: {profile['diet_style']}")
            if profile.get("allergies"):
                context_parts.append(f"Allergies to avoid mentioning: {', '.join(profile['allergies'])}")
        
        if pref_facts:
            likes = [f["fact_key"].replace("likes:", "") for f in pref_facts if f["fact_key"].startswith("likes:")]
            if likes:
                context_parts.append(f"User likes: {', '.join(likes[:3])}")
        
        context_parts.append("Make the tip actionable and encouraging. No emojis.")
        
        prompt = "\n".join(context_parts)
        
        messages = [
            {"role": "system", "content": "You are a friendly nutrition advisor. Give brief, practical tips."},
            {"role": "user", "content": prompt},
        ]
        
        tip = await openai_client.chat(messages=messages, temperature=0.8, max_tokens=100)
        
        return ApiResponse.success({
            "tip": tip.strip(),
            "generated_at": datetime.now(timezone.utc).isoformat(),
        })
        
    except Exception as e:
        # Fallback tip if AI fails
        return ApiResponse.success({
            "tip": "Eating slowly helps digestion and lets you enjoy each bite more.",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "fallback": True,
        })


@router.get("/todays-meals", response_model=ApiResponse)
async def get_todays_meals(user_id: str = "user_0001"):
    """
    Get meals logged today with their nourish tips.
    """
    try:
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        # Get today's date range
        today = datetime.now(timezone.utc).date()
        today_start = datetime(today.year, today.month, today.day, tzinfo=timezone.utc)
        
        # Get meals from today
        all_meals = await db.get_history(user_id, limit=50, offset=0)
        
        # Filter to today's meals
        todays_meals = []
        for meal in all_meals:
            meal_date = datetime.fromisoformat(meal["created_at"].replace("Z", "+00:00"))
            if meal_date.date() == today:
                todays_meals.append({
                    "meal_id": meal["meal_id"],
                    "title": meal["title"],
                    "created_at": meal["created_at"],
                    "tags": meal.get("tags", []),
                    "liked": meal.get("liked"),
                })
        
        # Generate nourish tips for each meal
        for meal in todays_meals:
            meal["nourish_tip"] = await _generate_nourish_tip(meal["title"], meal.get("tags", []))
        
        return ApiResponse.success({
            "date": today.isoformat(),
            "meals": todays_meals,
            "count": len(todays_meals),
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


async def _generate_nourish_tip(meal_title: str, tags: list[str]) -> str:
    """Generate a nourish tip for a specific meal."""
    try:
        prompt = f"Give one brief tip (1 sentence) to make '{meal_title}' healthier or more nutritious. Be specific and actionable. No emojis."
        
        messages = [
            {"role": "system", "content": "You are a nutrition advisor. Give brief, practical tips."},
            {"role": "user", "content": prompt},
        ]
        
        tip = await openai_client.chat(messages=messages, temperature=0.7, max_tokens=80)
        return tip.strip()
        
    except Exception:
        return "Add a side of vegetables to boost fiber and vitamins."


@router.get("/home-data", response_model=ApiResponse)
async def get_home_data(user_id: str = "user_0001"):
    """
    Get all data needed for home screen in one call.
    """
    try:
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        # Get profile
        profile = await db.get_profile(user_id)
        display_name = profile.get("display_name") if profile else None
        
        # Get today's meals
        today = datetime.now(timezone.utc).date()
        all_meals = await db.get_history(user_id, limit=20, offset=0)
        
        todays_meals = []
        for meal in all_meals:
            meal_date = datetime.fromisoformat(meal["created_at"].replace("Z", "+00:00"))
            if meal_date.date() == today:
                todays_meals.append({
                    "meal_id": meal["meal_id"],
                    "title": meal["title"],
                    "created_at": meal["created_at"],
                    "tags": meal.get("tags", []),
                    "image_url": meal.get("generated_image_path"),
                })
        
        # Generate nourish tips
        for meal in todays_meals:
            meal["nourish_tip"] = await _generate_nourish_tip(meal["title"], meal.get("tags", []))
        
        # Generate daily tip
        pref_facts = await db.get_top_preference_facts(user_id, limit=5)
        daily_tip = await _generate_daily_tip(profile, pref_facts)
        
        # Get suggested bites (use cache if available)
        suggested_response = await get_suggested_bites(user_id, refresh=False)
        suggested_bites = suggested_response.data.get("suggestions", []) if suggested_response.ok else []
        
        # Attach any generated images
        for bite in suggested_bites:
            sid = bite.get("suggestion_id", "")
            if sid in _suggested_images_cache and not bite.get("image_url"):
                bite["image_url"] = _suggested_images_cache[sid]
        
        return ApiResponse.success({
            "user": {
                "display_name": display_name,
                "has_profile": profile is not None,
            },
            "daily_tip": daily_tip,
            "todays_meals": todays_meals,
            "suggested_bites": suggested_bites,
            "date": today.isoformat(),
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


async def _generate_daily_tip(profile: dict | None, pref_facts: list[dict]) -> str:
    """Generate personalized daily tip."""
    try:
        context_parts = ["Generate a short, helpful nutrition tip (1-2 sentences max)."]
        
        if profile:
            if profile.get("goals"):
                context_parts.append(f"User goals: {', '.join(profile['goals'])}")
            if profile.get("diet_style"):
                context_parts.append(f"Diet style: {profile['diet_style']}")
        
        if pref_facts:
            likes = [f["fact_key"].replace("likes:", "") for f in pref_facts if f["fact_key"].startswith("likes:")]
            if likes:
                context_parts.append(f"User likes: {', '.join(likes[:3])}")
        
        context_parts.append("Make the tip actionable and encouraging. No emojis.")
        
        messages = [
            {"role": "system", "content": "You are a friendly nutrition advisor. Give brief, practical tips."},
            {"role": "user", "content": "\n".join(context_parts)},
        ]
        
        return (await openai_client.chat(messages=messages, temperature=0.8, max_tokens=100)).strip()
        
    except Exception:
        return "Eating slowly helps digestion and lets you enjoy each bite more."


@router.get("/suggested-bites", response_model=ApiResponse)
async def get_suggested_bites(user_id: str = "user_0001", refresh: bool = False):
    """
    Get AI-suggested meals for today based on user preferences.
    These are suggestions the user can tweak and log.
    """
    global _suggested_meals_cache
    
    try:
        today = datetime.now(timezone.utc).date().isoformat()
        cache_key = f"{user_id}_{today}"
        
        # Return cached if available and not forcing refresh
        if not refresh and cache_key in _suggested_meals_cache:
            return ApiResponse.success(_suggested_meals_cache[cache_key])
        
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        profile = await db.get_profile(user_id)
        pref_facts = await db.get_top_preference_facts(user_id, limit=10)
        
        # Build context for meal suggestions
        context_parts = []
        
        if profile:
            if profile.get("goals"):
                context_parts.append(f"Goals: {', '.join(profile['goals'])}")
            if profile.get("diet_style"):
                context_parts.append(f"Diet: {profile['diet_style']}")
            if profile.get("allergies"):
                context_parts.append(f"AVOID (allergies): {', '.join(profile['allergies'])}")
            if profile.get("dislikes"):
                context_parts.append(f"Dislikes: {', '.join(profile['dislikes'])}")
            if profile.get("likes"):
                context_parts.append(f"Likes: {', '.join(profile['likes'])}")
            if profile.get("cooking_skill"):
                context_parts.append(f"Skill: {profile['cooking_skill']}")
        
        if pref_facts:
            likes = [f["fact_key"].replace("likes:", "") for f in pref_facts if f["fact_key"].startswith("likes:")]
            if likes:
                context_parts.append(f"Learned preferences: {', '.join(likes[:5])}")
        
        context = "\n".join(context_parts) if context_parts else "No specific preferences known yet - suggest popular healthy options."
        
        prompt = f"""Generate exactly 2 personalized healthy meal suggestions for today.

User Context:
{context}

Return a JSON array with exactly 2 objects. Each object must have:
- "title": string (catchy, appetizing meal name like "Mediterranean Power Bowl")
- "summary": string (2 sentences describing the meal)
- "key_ingredients": array of 4-5 strings (main visible ingredients)
- "tweak_options": array of 3 strings (actionable improvements like "Add plant protein")
- "tags": array of strings (like "high-protein", "vegetarian", "quick")
- "science_note": string (one sentence about health benefit)

Make suggestions visually distinct - different cuisines, colors, presentations.
Example format: [{{"title": "...", "summary": "...", ...}}, {{"title": "...", ...}}]"""

        messages = [
            {"role": "system", "content": "You are a nutrition expert. Always respond with valid JSON arrays only, no markdown."},
            {"role": "user", "content": prompt},
        ]
        
        result = await openai_client.chat_json(messages=messages, temperature=0.8)
        print(f"DEBUG suggested-bites raw result: {result}")
        
        # Normalize result - could be array or object with suggestions key
        if isinstance(result, list):
            suggestions = result
        elif isinstance(result, dict):
            suggestions = result.get("suggestions", result.get("meals", [result]))
        else:
            suggestions = []
        
        # Add IDs and ensure structure
        processed = []
        for i, s in enumerate(suggestions[:2]):
            if not isinstance(s, dict):
                continue
            suggestion_id = f"daily_{uuid.uuid4().hex[:8]}"
            title = s.get("title", "")
            if not title or title == "":
                continue
                
            processed.append({
                "suggestion_id": suggestion_id,
                "title": title,
                "summary": s.get("summary", "A delicious and nutritious meal option."),
                "key_ingredients": s.get("key_ingredients", ["vegetables", "protein", "whole grains"]),
                "tweak_options": s.get("tweak_options", ["Add more protein", "Include vegetables", "Use healthy fats"]),
                "tags": s.get("tags", ["healthy"]),
                "science_note": s.get("science_note", "This meal provides balanced nutrition for sustained energy."),
                "image_url": None,
            })
        
        # If we didn't get good suggestions, use quality fallbacks
        if len(processed) < 2:
            processed = _get_fallback_suggestions()
        
        # Check for cached images and attach them
        for suggestion in processed:
            sid = suggestion.get("suggestion_id", "")
            if sid in _suggested_images_cache:
                suggestion["image_url"] = _suggested_images_cache[sid]
        
        result_data = {
            "suggestions": processed,
            "date": today,
        }
        
        # Cache for today (but can be refreshed)
        _suggested_meals_cache[cache_key] = result_data
        
        # Start image generation in background if not already generating
        suggestions_needing_images = [
            s for s in processed 
            if s.get("suggestion_id") and not s.get("image_url")
            and s.get("suggestion_id") not in _image_generation_tasks
        ]
        
        if suggestions_needing_images:
            for s in suggestions_needing_images:
                _image_generation_tasks[s["suggestion_id"]] = True
            asyncio.create_task(_generate_bite_images(user_id, suggestions_needing_images))
        
        return ApiResponse.success(result_data)
        
    except Exception as e:
        print(f"ERROR in suggested-bites: {e}")
        return ApiResponse.success({
            "suggestions": _get_fallback_suggestions(),
            "date": datetime.now(timezone.utc).date().isoformat(),
            "fallback": True,
        })


def _get_fallback_suggestions() -> list[dict]:
    """Return quality fallback suggestions"""
    return [
        {
            "suggestion_id": f"daily_{uuid.uuid4().hex[:8]}",
            "title": "Mediterranean Power Bowl",
            "summary": "A vibrant bowl packed with quinoa, roasted chickpeas, and fresh vegetables. Drizzled with lemon-tahini dressing for a satisfying lunch.",
            "key_ingredients": ["quinoa", "chickpeas", "cucumber", "cherry tomatoes", "feta cheese"],
            "tweak_options": ["Add grilled chicken", "Extra olive oil drizzle", "Include avocado"],
            "tags": ["vegetarian", "high-fiber", "mediterranean"],
            "science_note": "Quinoa provides complete protein with all essential amino acids for muscle repair.",
            "image_url": None,
        },
        {
            "suggestion_id": f"daily_{uuid.uuid4().hex[:8]}",
            "title": "Asian Salmon Stir-Fry",
            "summary": "Tender salmon pieces with colorful vegetables in a ginger-garlic sauce. Served over brown rice for a protein-packed dinner.",
            "key_ingredients": ["salmon", "broccoli", "bell peppers", "brown rice", "sesame seeds"],
            "tweak_options": ["Add edamame", "Use cauliflower rice", "Include leafy greens"],
            "tags": ["high-protein", "omega-3", "asian"],
            "science_note": "Salmon is rich in omega-3 fatty acids that support heart and brain health.",
            "image_url": None,
        }
    ]


async def _generate_bite_images(user_id: str, suggestions: list[dict]):
    """Background task to generate images for suggested bites"""
    global _suggested_images_cache, _image_generation_tasks
    
    # Different presentation styles for variety
    presentation_styles = [
        ("rustic wooden table, warm natural lighting, overhead shot", "artisan ceramic bowl"),
        ("marble countertop, soft diffused lighting, 45-degree angle", "modern white plate"),
        ("dark slate background, dramatic side lighting, close-up", "cast iron skillet"),
        ("bright kitchen setting, natural window light", "colorful ceramic plate with fresh herbs"),
    ]
    
    async def generate_one(suggestion: dict, index: int):
        suggestion_id = suggestion.get("suggestion_id", "")
        title = suggestion.get("title", "Healthy Meal")
        key_ingredients = suggestion.get("key_ingredients", [])
        
        # Skip if already generated
        if suggestion_id in _suggested_images_cache:
            return
        
        try:
            # Build ingredient description
            ingredients_desc = ""
            if key_ingredients:
                ingredients_desc = f" featuring visible {', '.join(key_ingredients[:4])}"
            
            # Vary the presentation style
            style_idx = index % len(presentation_styles)
            background, plating = presentation_styles[style_idx]
            
            prompt = (
                f"Professional food photography of {title}{ingredients_desc}. "
                f"Served in a {plating}. {background}. "
                f"Appetizing, realistic, restaurant-quality presentation. "
                f"Sharp focus on the food, vibrant colors, no text or labels or watermarks."
            )
            
            # Generate image
            dalle_url = await openai_client.generate_image(prompt, size="1024x1024", quality="standard")
            
            if dalle_url:
                # Download and save locally
                local_path = await _download_and_save_image(user_id, dalle_url, suggestion_id)
                if local_path:
                    filename = Path(local_path).name
                    local_url = f"http://127.0.0.1:8080/images/{user_id}/{filename}"
                    _suggested_images_cache[suggestion_id] = local_url
                    print(f"Generated image for {title}: {local_url}")
                    
        except Exception as e:
            print(f"Failed to generate image for {title}: {e}")
    
    # Generate images in parallel
    tasks = [generate_one(s, i) for i, s in enumerate(suggestions)]
    await asyncio.gather(*tasks, return_exceptions=True)
    
    # Mark generation complete
    for s in suggestions:
        sid = s.get("suggestion_id", "")
        if sid:
            _image_generation_tasks[sid] = False


async def _download_and_save_image(user_id: str, image_url: str, suggestion_id: str) -> str | None:
    """Download image from URL and save locally"""
    try:
        images_dir = settings.user_images_dir(user_id)
        images_dir.mkdir(parents=True, exist_ok=True)
        
        async with httpx.AsyncClient() as client:
            response = await client.get(image_url, timeout=30.0)
            if response.status_code == 200:
                filename = f"bite_{suggestion_id}.jpg"
                path = images_dir / filename
                with open(path, "wb") as f:
                    f.write(response.content)
                return str(path)
    except Exception as e:
        print(f"Failed to download image: {e}")
    return None


@router.get("/bite-images", response_model=ApiResponse)
async def get_bite_images(user_id: str = "user_0001"):
    """
    Get generated images for suggested bites.
    Frontend can poll this to get images as they're generated.
    """
    global _suggested_images_cache
    
    # Return all cached images for this user's suggestions
    return ApiResponse.success({
        "images": _suggested_images_cache,
        "generating": any(_image_generation_tasks.values()),
    })


@router.post("/refresh-suggestions", response_model=ApiResponse)
async def refresh_suggestions(user_id: str = "user_0001"):
    """
    Force refresh suggested bites based on updated preferences.
    Called after profile changes or chat updates.
    """
    global _suggested_meals_cache
    
    # Clear cache for this user
    today = datetime.now(timezone.utc).date().isoformat()
    cache_key = f"{user_id}_{today}"
    if cache_key in _suggested_meals_cache:
        del _suggested_meals_cache[cache_key]
    
    # Return fresh suggestions
    return await get_suggested_bites(user_id, refresh=True)


from pydantic import BaseModel as TweakSelectionBase

class TweakSelectionRequest(TweakSelectionBase):
    selected_tweaks: list[str] = []

@router.post("/tweak-selection", response_model=ApiResponse)
async def save_tweak_selection(
    request: TweakSelectionRequest,
    user_id: str = "user_0001",
    suggestion_id: str = "",
):
    """
    Save user's tweak selections as preferences.
    This helps learn what improvements the user prefers.
    """
    try:
        db = await get_db(user_id)
        
        # Save each selected tweak as a preference
        for tweak in request.selected_tweaks:
            # Normalize tweak to preference key
            fact_key = f"prefers:{tweak.lower().replace(' ', '_')}"
            await db.update_preference_fact(
                user_id=user_id,
                fact_key=fact_key,
                delta=0.3,  # Moderate positive signal
                source_meal_id=suggestion_id,
            )
        
        return ApiResponse.success({
            "saved": len(request.selected_tweaks),
            "message": "Preferences updated!"
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))
