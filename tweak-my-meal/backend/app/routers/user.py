"""
User Profile API Routes
"""
from fastapi import APIRouter, HTTPException

from ..schemas.api import (
    ApiResponse, CreateProfileRequest, CreateProfileResponse,
    UserSummaryResponse, PreferenceFactSummary
)
from ..db import get_db
from ..config import settings

router = APIRouter(prefix="/api/user", tags=["user"])


@router.post("/profile", response_model=ApiResponse)
async def create_or_update_profile(request: CreateProfileRequest):
    """
    Create or update user profile.
    Creates user folder structure if missing.
    """
    try:
        user_id = request.user_id
        db = await get_db(user_id)
        
        # Ensure user exists
        storage_root = await db.ensure_user(user_id)
        
        # Ensure directories exist
        settings.user_images_dir(user_id).mkdir(parents=True, exist_ok=True)
        settings.user_vector_dir(user_id).mkdir(parents=True, exist_ok=True)
        
        # Upsert profile
        profile_data = request.profile.model_dump(exclude_none=True)
        version = await db.upsert_profile(user_id, profile_data)
        
        # Generate summary
        profile = await db.get_profile(user_id)
        summary = _generate_profile_summary(profile)
        
        return ApiResponse.success(CreateProfileResponse(
            user_id=user_id,
            storage_root=storage_root,
            profile_version=version,
            profile_summary=summary,
        ))
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


@router.get("/summary", response_model=ApiResponse)
async def get_user_summary(user_id: str = "user_0001"):
    """
    Get user summary including profile and top preferences.
    """
    try:
        db = await get_db(user_id)
        
        # Check user exists
        user = await db.get_user(user_id)
        if not user:
            return ApiResponse.failure("NOT_FOUND", f"User {user_id} not found")
        
        # Get profile
        profile = await db.get_profile(user_id)
        summary = _generate_profile_summary(profile)
        
        # Get top preferences
        pref_facts = await db.get_top_preference_facts(user_id, limit=10)
        top_prefs = [
            PreferenceFactSummary(fact_key=f["fact_key"], strength=f["strength"])
            for f in pref_facts
        ]
        
        return ApiResponse.success(UserSummaryResponse(
            user_id=user_id,
            profile_summary=summary,
            top_preferences=top_prefs,
        ))
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


def _generate_profile_summary(profile: dict | None) -> str:
    """Generate human-readable profile summary"""
    if not profile:
        return "New user - complete onboarding to personalize"
    
    parts = []
    if profile.get("display_name"):
        parts.append(profile["display_name"])
    if profile.get("diet_style"):
        parts.append(profile["diet_style"])
    if profile.get("cooking_skill"):
        parts.append(f"{profile['cooking_skill']} cook")
    if profile.get("goals"):
        parts.append(f"Goals: {', '.join(profile['goals'][:2])}")
    if profile.get("allergies"):
        parts.append(f"Allergies: {', '.join(profile['allergies'])}")
    
    return " | ".join(parts) if parts else "Basic profile saved"
