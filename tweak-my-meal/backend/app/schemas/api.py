"""
API Request/Response Schemas - matching docs/02-api-contract.md
"""
from typing import Optional, Literal, Any
from pydantic import BaseModel, Field

from .agents import VisionResult, Suggestion, RecipeResult


# ============================================================================
# Response Envelope
# ============================================================================

class ErrorDetail(BaseModel):
    code: str
    message: str
    details: Optional[dict] = None


class ApiResponse(BaseModel):
    ok: bool
    data: Optional[Any] = None
    error: Optional[ErrorDetail] = None

    @classmethod
    def success(cls, data: Any) -> "ApiResponse":
        return cls(ok=True, data=data)

    @classmethod
    def failure(cls, code: str, message: str, details: Optional[dict] = None) -> "ApiResponse":
        return cls(ok=False, error=ErrorDetail(code=code, message=message, details=details))


# ============================================================================
# User Profile
# ============================================================================

class UserProfileInput(BaseModel):
    display_name: Optional[str] = None
    diet_style: Optional[str] = None
    goals: list[str] = Field(default_factory=list)
    allergies: list[str] = Field(default_factory=list)
    dislikes: list[str] = Field(default_factory=list)
    likes: list[str] = Field(default_factory=list)
    cooking_skill: Optional[Literal["beginner", "intermediate", "advanced"]] = None
    time_per_meal_minutes: Optional[int] = None
    budget: Optional[Literal["low", "medium", "high"]] = None
    household_size: Optional[int] = None
    equipment: list[str] = Field(default_factory=list)
    units: str = "metric"
    notes: Optional[str] = None


class CreateProfileRequest(BaseModel):
    user_id: str = "user_0001"
    profile: UserProfileInput


class CreateProfileResponse(BaseModel):
    user_id: str
    storage_root: str
    profile_version: int
    profile_summary: str


# ============================================================================
# Chat Turn
# ============================================================================

class ClientContext(BaseModel):
    max_time_minutes: Optional[int] = None


class ChatTurnRequest(BaseModel):
    user_id: str = "user_0001"
    session_id: str
    text: Optional[str] = None
    mode_hint: Literal["auto", "meal", "ingredients"] = "auto"
    client_context: Optional[ClientContext] = None


class NextAction(BaseModel):
    type: str
    hint: str


class SourceInfo(BaseModel):
    input_kind: str
    vision_result: Optional[VisionResult] = None


class FollowUpResponse(BaseModel):
    kind: Literal["follow_up"] = "follow_up"
    session_id: str
    questions: list[str]
    blocking: bool = True


class SuggestionsResponse(BaseModel):
    kind: Literal["suggestions"] = "suggestions"
    session_id: str
    source: SourceInfo
    suggestions: list[Suggestion]
    next_action: NextAction = NextAction(
        type="select_suggestion",
        hint="Pick one option to get the full recipe"
    )


class RecipeResponse(BaseModel):
    kind: Literal["recipe"] = "recipe"
    session_id: str
    meal_id: str
    recipe: RecipeResult
    image_url: Optional[str] = None


# ============================================================================
# Chat Select
# ============================================================================

class ChatSelectRequest(BaseModel):
    user_id: str = "user_0001"
    session_id: str
    suggestion_id: str


# ============================================================================
# Feedback
# ============================================================================

class FeedbackRequest(BaseModel):
    user_id: str = "user_0001"
    meal_id: str
    liked: bool
    cooked_again: bool = False
    tags: list[str] = Field(default_factory=list)
    notes: Optional[str] = None


class FeedbackResponse(BaseModel):
    updated_profile_summary: str
    memory_items_written: int
    preference_facts_updated: int


# ============================================================================
# History
# ============================================================================

class HistoryItem(BaseModel):
    meal_id: str
    created_at: str
    title: str
    liked: Optional[bool] = None
    cooked_again: Optional[bool] = None
    tags: list[str] = Field(default_factory=list)


class HistoryResponse(BaseModel):
    items: list[HistoryItem]
    limit: int
    offset: int


# ============================================================================
# User Summary
# ============================================================================

class PreferenceFactSummary(BaseModel):
    fact_key: str
    strength: float


class UserSummaryResponse(BaseModel):
    user_id: str
    profile_summary: str
    top_preferences: list[PreferenceFactSummary]
