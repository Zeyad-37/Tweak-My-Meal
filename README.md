# Tweak My Meal 🥗

An AI-powered nutrition advisor that helps you make healthier food choices. Upload a photo of your meal or describe what you ate, and get personalized healthier alternatives with full recipes.

## Features

- **Image Analysis**: Upload food photos for AI-powered meal recognition
- **Smart Suggestions**: Get 3-5 healthier alternatives tailored to your preferences
- **Full Recipes**: Detailed recipes with ingredients, steps, and nutrition estimates
- **Learning System**: The app learns your preferences over time
- **Dietary Constraints**: Respects allergies, dislikes, and dietary restrictions

## Architecture

```
┌─────────────────┐     ┌─────────────────────────────────────────┐
│   Flutter App   │────▶│          FastAPI Backend                │
│  (Web/Mobile)   │     │                                         │
└─────────────────┘     │  ┌─────────────────────────────────┐   │
                        │  │         Orchestrator            │   │
                        │  │  (Coordinates Agent Pipeline)   │   │
                        │  └─────────────┬───────────────────┘   │
                        │                │                        │
                        │  ┌─────────────▼───────────────────┐   │
                        │  │          AI Agents              │   │
                        │  │  • Vision Agent (GPT-4o)        │   │
                        │  │  • Meal Understanding Agent     │   │
                        │  │  • Suggestion Agent             │   │
                        │  │  • Recipe Agent                 │   │
                        │  │  • Memory Update Agent          │   │
                        │  └─────────────┬───────────────────┘   │
                        │                │                        │
                        │  ┌─────────────▼───────────────────┐   │
                        │  │         Storage                 │   │
                        │  │  • SQLite (profiles, meals)     │   │
                        │  │  • Vector Store (memories)      │   │
                        │  └─────────────────────────────────┘   │
                        └─────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Python 3.10+
- Flutter 3.2+
- OpenAI API Key

### 1. Clone the Repository

```bash
git clone https://github.com/Zeyad-37/Tweak-My-Meal.git
cd Tweak-My-Meal
```

### 2. Set Up Environment Variables

```bash
# Backend
cp .env.example .env
# Edit .env and add your OpenAI API key

# Flutter
cp assets/env.example assets/env
# Edit assets/env and add your OpenAI API key
```

### 3. Start the Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload
```

### 4. Start the Flutter App

```bash
# In a new terminal, from project root
flutter pub get
flutter run -d chrome
```

### 5. Use the App

1. Complete the onboarding chat (or click "Skip")
2. Type a meal description or upload a food photo
3. Select a healthier suggestion
4. Get the full recipe
5. Provide feedback to help the AI learn your preferences

---

## API Reference

Base URL: `http://127.0.0.1:8080`

All responses follow this envelope format:
```json
{
  "ok": true,
  "data": { ... },
  "error": null
}
```

### Authentication

No authentication required for MVP (single user: `user_0001`).

---

### Create/Update User Profile

**POST** `/api/user/profile`

Create or update user profile with dietary preferences.

```bash
curl -X POST http://127.0.0.1:8080/api/user/profile \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user_0001",
    "profile": {
      "display_name": "John",
      "cooking_skill": "intermediate",
      "goals": ["lose weight", "eat healthier"],
      "allergies": ["peanuts", "shellfish"],
      "dislikes": ["mushrooms", "olives"],
      "likes": ["spicy food", "asian cuisine"],
      "equipment": ["stovetop", "oven", "air fryer"],
      "time_per_meal_minutes": 30,
      "diet_style": "mediterranean",
      "household_size": 2
    }
  }'
```

**Response:**
```json
{
  "ok": true,
  "data": {
    "user_id": "user_0001",
    "storage_root": "./local_data/user_0001",
    "profile_version": 1,
    "profile_summary": "John | intermediate cook | Goals: lose weight, eat healthier"
  }
}
```

---

### Get User Summary

**GET** `/api/user/summary?user_id=user_0001`

Get profile summary and learned preferences.

```bash
curl "http://127.0.0.1:8080/api/user/summary?user_id=user_0001"
```

**Response:**
```json
{
  "ok": true,
  "data": {
    "user_id": "user_0001",
    "profile_summary": "John | intermediate cook | Goals: lose weight",
    "top_preferences": [
      { "fact_key": "likes:spicy", "strength": 0.7 },
      { "fact_key": "likes:asian_cuisine", "strength": 0.6 }
    ]
  }
}
```

---

### Chat Turn (Text Only)

**POST** `/api/chat/turn`

Send a text description of a meal to get healthier suggestions.

```bash
curl -X POST http://127.0.0.1:8080/api/chat/turn \
  -F "user_id=user_0001" \
  -F "session_id=my-session-123" \
  -F "text=I just had a greasy cheeseburger with fries"
```

**Response (Suggestions):**
```json
{
  "ok": true,
  "data": {
    "kind": "suggestions",
    "session_id": "my-session-123",
    "source": {
      "input_kind": "text_meal",
      "vision_result": null
    },
    "suggestions": [
      {
        "suggestion_id": "sug_1",
        "title": "Turkey Burger with Sweet Potato Wedges",
        "summary": "Lean turkey patty with air-fried sweet potato wedges",
        "health_rationale": ["Lower fat", "More fiber"],
        "tags": ["high-protein", "quick"],
        "estimated_time_minutes": 25,
        "difficulty": "easy"
      }
    ],
    "next_action": {
      "type": "select_suggestion",
      "hint": "Pick one option to get the full recipe"
    }
  }
}
```

---

### Chat Turn (With Image)

**POST** `/api/chat/turn`

Upload a food photo for AI analysis and suggestions.

```bash
curl -X POST http://127.0.0.1:8080/api/chat/turn \
  -F "user_id=user_0001" \
  -F "session_id=my-session-456" \
  -F "text=Make this healthier" \
  -F "images=@/path/to/food-photo.jpg"
```

The response includes vision analysis:
```json
{
  "ok": true,
  "data": {
    "kind": "suggestions",
    "session_id": "my-session-456",
    "source": {
      "input_kind": "meal_photo",
      "vision_result": {
        "kind": "meal_photo",
        "confidence": 0.92,
        "detected": {
          "meal_name": "Pepperoni Pizza",
          "ingredients": [
            { "name": "pizza dough", "quantity_hint": "1 large" },
            { "name": "pepperoni", "quantity_hint": "generous" }
          ],
          "cuisine_hint": "Italian"
        }
      }
    },
    "suggestions": [ ... ]
  }
}
```

---

### Select Suggestion (Get Recipe)

**POST** `/api/chat/select`

Select a suggestion to generate the full recipe.

```bash
curl -X POST http://127.0.0.1:8080/api/chat/select \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user_0001",
    "session_id": "my-session-123",
    "suggestion_id": "sug_1"
  }'
```

**Response:**
```json
{
  "ok": true,
  "data": {
    "kind": "recipe",
    "session_id": "my-session-123",
    "meal_id": "uuid-of-saved-meal",
    "recipe": {
      "name": "Turkey Burger with Sweet Potato Wedges",
      "summary": "A lean, flavorful burger with crispy sweet potato wedges",
      "health_rationale": ["50% less fat than beef", "Rich in vitamin A"],
      "ingredients": [
        {
          "name": "Ground turkey",
          "quantity": "400g",
          "optional": false,
          "substitutes": ["Chicken mince"]
        }
      ],
      "steps": [
        "Preheat air fryer to 200°C",
        "Mix turkey with seasonings...",
        "Form into patties..."
      ],
      "time_minutes": 25,
      "difficulty": "easy",
      "equipment": ["Air fryer", "Stovetop"],
      "servings": 2,
      "nutrition_estimate": {
        "calories": 420,
        "protein_g": 35,
        "carbs_g": 38,
        "fat_g": 12
      },
      "warnings": ["Ensure turkey is cooked to 165°F/74°C"]
    }
  }
}
```

---

### Submit Feedback

**POST** `/api/feedback`

Provide feedback on a meal to help the AI learn your preferences.

```bash
curl -X POST http://127.0.0.1:8080/api/feedback \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user_0001",
    "meal_id": "uuid-of-saved-meal",
    "liked": true,
    "cooked_again": true,
    "tags": ["tasty", "easy", "family-approved"],
    "notes": "Kids loved it! Will make again."
  }'
```

**Response:**
```json
{
  "ok": true,
  "data": {
    "updated_profile_summary": "John | intermediate cook | Goals: lose weight",
    "memory_items_written": 3,
    "preference_facts_updated": 5
  }
}
```

---

### Get Meal History

**GET** `/api/history?user_id=user_0001&limit=50&offset=0`

Retrieve past meals and their outcomes.

```bash
curl "http://127.0.0.1:8080/api/history?user_id=user_0001&limit=10"
```

**Response:**
```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "meal_id": "uuid",
        "created_at": "2026-01-29T12:30:00Z",
        "title": "Turkey Burger with Sweet Potato Wedges",
        "liked": true,
        "cooked_again": true,
        "tags": ["high-protein", "quick"]
      }
    ],
    "limit": 10,
    "offset": 0
  }
}
```

---

## Project Structure

```
├── backend/                 # FastAPI Backend
│   ├── app/
│   │   ├── agents/          # AI Agents (Vision, Suggestion, Recipe, etc.)
│   │   ├── db/              # Database (SQLite)
│   │   ├── routers/         # API Routes
│   │   ├── schemas/         # Pydantic Models
│   │   ├── services/        # Orchestrator, OpenAI Client, Vector Store
│   │   ├── config.py        # Configuration
│   │   └── main.py          # FastAPI App
│   └── requirements.txt
│
├── lib/                     # Flutter App
│   ├── core/                # Theme, Config
│   ├── models/              # Data Models
│   ├── providers/           # State Management
│   ├── services/            # API Client, OpenAI Service
│   └── ui/
│       ├── screens/         # Onboarding, Chat, Dashboard
│       └── widgets/         # Reusable Components
│
├── docs/                    # Documentation
│   ├── 01-architecture-local.md
│   ├── 02-api-contract.md
│   ├── 03-data-model.md
│   ├── 04-agent-io-schemas.md
│   └── 12-agents-vision-and-flow.md
│
├── .env.example             # Environment template
└── assets/env.example       # Flutter env template
```

---

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `OPEN_AI_KEY` | OpenAI API Key (for GPT-4o) | Yes |
| `GEMINI_API_KEY` | Google Gemini Key (legacy, unused) | No |

---

## Tech Stack

- **Backend**: FastAPI, Python 3.10+, SQLite, OpenAI GPT-4o
- **Frontend**: Flutter 3.2+, Provider, Go Router
- **AI**: OpenAI GPT-4o (text + vision), text-embedding-3-small

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
