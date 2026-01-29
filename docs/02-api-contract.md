# FILE: docs/02-api-contract.md

# API Contract (Local FastAPI) — MVP

Base URL (local): http://127.0.0.1:8080

All responses are JSON with UTF-8. Metric units only.

## Conventions

### Response envelope
All endpoints return one of:
- { "ok": true, "data": ... }
- { "ok": false, "error": { "code": "...", "message": "...", "details": {...optional...} } }

### Error codes (non-exhaustive)
- VALIDATION_ERROR (400)
- NOT_FOUND (404)
- CONFLICT (409)
- MODEL_ERROR (502)
- INTERNAL_ERROR (500)

### IDs
- user_id: fixed user_0001 for MVP (single user), returned by profile endpoint.
- session_id: client-generated UUID recommended.
- suggestion_id, meal_id: server-generated UUID.

---

## 1) Create/Update User Profile

### POST /api/user/profile
Creates the single local user folder if missing and upserts the profile.

#### Request JSON
{
  "user_id": "user_0001",
  "profile": {
    "display_name": "string",
    "diet_style": "string",
    "goals": ["string"],
    "allergies": ["string"],
    "dislikes": ["string"],
    "likes": ["string"],
    "cooking_skill": "beginner|intermediate|advanced",
    "time_per_meal_minutes": 20,
    "budget": "low|medium|high",
    "household_size": 1,
    "equipment": ["string"],
    "units": "metric",
    "notes": "string"
  }
}

#### Response
{
  "ok": true,
  "data": {
    "user_id": "user_0001",
    "storage_root": "./local_data/user_0001",
    "profile_version": 1,
    "profile_summary": "string"
  }
}

---

## 2) Chat Turn (UI chat entry point)

### POST /api/chat/turn
Accepts:
- text-only turn, OR
- multipart with images

The backend may respond with:
- follow-up questions
- suggestions (after vision + suggestion agent)
- recipe (if the system can proceed without explicit selection)

### Variant A: JSON (text-only)
Content-Type: application/json

#### Request
{
  "user_id": "user_0001",
  "session_id": "uuid-string",
  "text": "string",
  "mode_hint": "auto|meal|ingredients",
  "client_context": {
    "max_time_minutes": 20
  }
}

### Variant B: Multipart (text + images)
Content-Type: multipart/form-data

#### Fields
- user_id (string)
- session_id (string)
- text (string, optional)
- mode_hint (auto|meal|ingredients, optional)
- client_context (stringified JSON, optional)
- images (one or more files)

Example curl:
curl -X POST "http://127.0.0.1:8080/api/chat/turn" \
  -F 'user_id=user_0001' \
  -F 'session_id=11111111-1111-1111-1111-111111111111' \
  -F 'text=Make this healthier' \
  -F 'images=@/path/to/photo.jpg'

### Response type: Follow-up questions
{
  "ok": true,
  "data": {
    "kind": "follow_up",
    "session_id": "uuid",
    "questions": [
      "Is this meant to be a main meal or a snack?",
      "Do you have an oven or only stovetop?"
    ],
    "blocking": true
  }
}

### Response type: Suggestions
{
  "ok": true,
  "data": {
    "kind": "suggestions",
    "session_id": "uuid",
    "source": {
      "input_kind": "meal_photo|ingredients_photo|text_meal|text_ingredients",
      "vision_result": { }
    },
    "suggestions": [
      {
        "suggestion_id": "uuid",
        "title": "string",
        "summary": "string",
        "health_rationale": ["string"],
        "tags": ["string"],
        "estimated_time_minutes": 25,
        "difficulty": "easy|medium|hard"
      }
    ],
    "next_action": {
      "type": "select_suggestion",
      "hint": "Pick one option to get the full recipe"
    }
  }
}

### Response type: Recipe
{
  "ok": true,
  "data": {
    "kind": "recipe",
    "session_id": "uuid",
    "meal_id": "uuid",
    "recipe": { }
  }
}

---

## 3) Select a Suggestion (generate recipe)

### POST /api/chat/select

#### Request
{
  "user_id": "user_0001",
  "session_id": "uuid",
  "suggestion_id": "uuid"
}

#### Response
{
  "ok": true,
  "data": {
    "kind": "recipe",
    "session_id": "uuid",
    "meal_id": "uuid",
    "recipe": { }
  }
}

---

## 4) Feedback (like/dislike + learning)

### POST /api/feedback

#### Request
{
  "user_id": "user_0001",
  "meal_id": "uuid",
  "liked": true,
  "cooked_again": false,
  "tags": ["too_spicy", "too_long", "easy", "tasty"],
  "notes": "string"
}

#### Response
{
  "ok": true,
  "data": {
    "updated_profile_summary": "string",
    "memory_items_written": 3,
    "preference_facts_updated": 5
  }
}

---

## 5) History (liked/disliked meals)

### GET /api/history?user_id=user_0001&limit=50&offset=0

#### Response
{
  "ok": true,
  "data": {
    "items": [
      {
        "meal_id": "uuid",
        "created_at": "iso-8601",
        "title": "string",
        "liked": true,
        "cooked_again": false,
        "tags": ["string"]
      }
    ],
    "limit": 50,
    "offset": 0
  }
}

---

## 6) User Summary (for UI header)

### GET /api/user/summary?user_id=user_0001

#### Response
{
  "ok": true,
  "data": {
    "user_id": "user_0001",
    "profile_summary": "string",
    "top_preferences": [
      { "fact_key": "likes:spicy", "strength": 1.4 },
      { "fact_key": "avoid:cilantro", "strength": 2.0 }
    ]
  }
}
