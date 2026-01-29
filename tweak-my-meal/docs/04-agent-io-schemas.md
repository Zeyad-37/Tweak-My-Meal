# FILE: docs/04-agent-io-schemas.md

# Agent I/O Schemas (Canonical) — MVP

All agent outputs MUST be valid JSON matching these shapes.
No markdown, no prose outside JSON.

## 1) VisionResult

Purpose: classify image as meal vs ingredients and extract normalized items.

{
  "kind": "meal_photo|ingredients_photo|unknown",
  "confidence": 0.0,
  "detected": {
    "meal_name": "string|null",
    "ingredients": [
      { "name": "string", "quantity_hint": "string|null" }
    ],
    "cuisine_hint": "string|null",
    "notes": "string|null"
  },
  "warnings": ["string"],
  "follow_up_questions": ["string"]
}

Rules:
- If kind == meal_photo, prefer detected.meal_name and optionally list visible components in ingredients.
- If kind == ingredients_photo, populate detected.ingredients with best-effort normalized names.
- If uncertain, set kind == unknown and add follow_up_questions.

---

## 2) SuggestionsResult

Purpose: propose high-level healthier options (no full recipe).

{
  "input_kind": "meal_photo|ingredients_photo|text_meal|text_ingredients",
  "suggestions": [
    {
      "suggestion_id": "string",
      "title": "string",
      "summary": "string",
      "health_rationale": ["string"],
      "tags": ["string"],
      "estimated_time_minutes": 0,
      "difficulty": "easy|medium|hard",
      "requires_user_choice": true
    }
  ],
  "follow_up_questions": ["string"]
}

Rules:
- For meal inputs: suggestions are healthier variants of the same meal.
- For ingredients inputs: suggestions are 3–5 meal ideas using those ingredients.
- If missing key constraints (equipment/time), ask follow-up_questions.

---

## 3) RecipeResult

Purpose: generate the final recipe for one chosen suggestion.

{
  "name": "string",
  "summary": "string",
  "health_rationale": ["string"],
  "ingredients": [
    {
      "name": "string",
      "quantity": "string",
      "optional": false,
      "substitutes": ["string"]
    }
  ],
  "steps": ["string"],
  "time_minutes": 0,
  "difficulty": "easy|medium|hard",
  "equipment": ["string"],
  "servings": 1,
  "nutrition_estimate": {
    "calories": null,
    "protein_g": null,
    "carbs_g": null,
    "fat_g": null
  },
  "warnings": ["string"]
}

Rules:
- MUST respect allergies/dislikes.
- MUST adapt difficulty to user cooking skill.
- nutrition_estimate fields are nullable for MVP (macros later).

---

## 4) MemoryWriteResult

Purpose: convert feedback/outcome into memory facts and profile updates.

{
  "memory_items": [
    {
      "text": "string",
      "kind": "like|dislike|constraint|pattern",
      "salience": 0.0
    }
  ],
  "preference_facts": [
    {
      "fact_key": "string",
      "delta_strength": 0.0,
      "reason": "string"
    }
  ],
  "profile_patch": {
    "likes_add": ["string"],
    "dislikes_add": ["string"],
    "notes_append": ["string"]
  }
}

Rules:
- memory_items.text should be short, single-sentence facts.
- fact_key examples:
  - likes:spicy
  - avoid:cream_sauces
  - prefers:quick_meals
  - equipment:airfryer
  - goal:high_protein

---

## 5) ChatTurnResponse (Backend output shape)

The backend returns one of:

### Follow-up
{
  "kind": "follow_up",
  "session_id": "string",
  "questions": ["string"],
  "blocking": true
}

### Suggestions
{
  "kind": "suggestions",
  "session_id": "string",
  "source": {
    "input_kind": "string",
    "vision_result": {
      "kind": "string",
      "confidence": 0.0,
      "detected": {},
      "warnings": [],
      "follow_up_questions": []
    }
  },
  "suggestions": [
    {
      "suggestion_id": "string",
      "title": "string",
      "summary": "string",
      "health_rationale": [],
      "tags": [],
      "estimated_time_minutes": 0,
      "difficulty": "easy"
    }
  ],
  "next_action": { "type": "select_suggestion", "hint": "string" }
}

### Recipe
{
  "kind": "recipe",
  "session_id": "string",
  "meal_id": "string",
  "recipe": {
    "name": "string",
    "summary": "string",
    "health_rationale": [],
    "ingredients": [],
    "steps": [],
    "time_minutes": 0,
    "difficulty": "easy",
    "equipment": [],
    "servings": 1,
    "nutrition_estimate": {
      "calories": null,
      "protein_g": null,
      "carbs_g": null,
      "fat_g": null
    },
    "warnings": []
  }
}
