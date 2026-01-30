"""
Agent I/O Schemas - Pydantic models matching docs/04-agent-io-schemas.md
"""
from typing import Optional, Literal
from pydantic import BaseModel, Field


# ============================================================================
# 1) VisionResult
# ============================================================================

class DetectedItem(BaseModel):
    name: str
    quantity_hint: Optional[str] = None


class VisionDetected(BaseModel):
    meal_name: Optional[str] = None
    ingredients: list[DetectedItem] = Field(default_factory=list)
    cuisine_hint: Optional[str] = None
    notes: Optional[str] = None


class VisionResult(BaseModel):
    kind: Literal["meal_photo", "ingredients_photo", "unknown"]
    confidence: float = Field(ge=0.0, le=1.0)
    detected: VisionDetected = Field(default_factory=VisionDetected)
    warnings: list[str] = Field(default_factory=list)
    follow_up_questions: list[str] = Field(default_factory=list)


# ============================================================================
# 2) SuggestionsResult
# ============================================================================

class Suggestion(BaseModel):
    suggestion_id: str
    title: str
    summary: str
    health_rationale: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    key_ingredients: list[str] = Field(default_factory=list)  # Main 3-5 ingredients for image generation
    tweak_options: list[str] = Field(default_factory=list)  # Improvement options like "Add plant protein"
    estimated_time_minutes: int = 30
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    requires_user_choice: bool = True
    image_url: Optional[str] = None


class SuggestionsResult(BaseModel):
    input_kind: Literal["meal_photo", "ingredients_photo", "text_meal", "text_ingredients"]
    suggestions: list[Suggestion] = Field(default_factory=list)
    follow_up_questions: list[str] = Field(default_factory=list)


# ============================================================================
# 3) RecipeResult
# ============================================================================

class RecipeIngredient(BaseModel):
    name: str
    quantity: str
    optional: bool = False
    substitutes: list[str] = Field(default_factory=list)


class NutritionEstimate(BaseModel):
    calories: Optional[int] = None
    protein_g: Optional[int] = None
    carbs_g: Optional[int] = None
    fat_g: Optional[int] = None


class RecipeResult(BaseModel):
    name: str
    summary: str
    health_rationale: list[str] = Field(default_factory=list)
    ingredients: list[RecipeIngredient] = Field(default_factory=list)
    steps: list[str] = Field(default_factory=list)
    time_minutes: int = 30
    difficulty: Literal["easy", "medium", "hard"] = "medium"
    equipment: list[str] = Field(default_factory=list)
    servings: int = 1
    nutrition_estimate: NutritionEstimate = Field(default_factory=NutritionEstimate)
    warnings: list[str] = Field(default_factory=list)


# ============================================================================
# 4) MemoryWriteResult
# ============================================================================

class MemoryItem(BaseModel):
    text: str
    kind: Literal["like", "dislike", "constraint", "pattern"]
    salience: float = Field(ge=0.0, le=1.0, default=0.5)


class PreferenceFact(BaseModel):
    fact_key: str
    delta_strength: float
    reason: str


class ProfilePatch(BaseModel):
    likes_add: list[str] = Field(default_factory=list)
    dislikes_add: list[str] = Field(default_factory=list)
    notes_append: list[str] = Field(default_factory=list)


class MemoryWriteResult(BaseModel):
    memory_items: list[MemoryItem] = Field(default_factory=list)
    preference_facts: list[PreferenceFact] = Field(default_factory=list)
    profile_patch: ProfilePatch = Field(default_factory=ProfilePatch)


# ============================================================================
# Internal: Normalized Input (from Meal Understanding Agent)
# ============================================================================

class NormalizedInput(BaseModel):
    input_kind: Literal["text_meal", "text_ingredients", "meal_photo", "ingredients_photo", "unknown"]
    meal_name: Optional[str] = None
    ingredients: list[str] = Field(default_factory=list)
    max_time_minutes: Optional[int] = None
    equipment_overrides: list[str] = Field(default_factory=list)
    missing_info_questions: list[str] = Field(default_factory=list)
