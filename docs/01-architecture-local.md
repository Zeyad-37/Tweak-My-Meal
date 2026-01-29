# FILE: docs/01-architecture-local.md

# Local-First Architecture (Flutter Web + FastAPI + Gemini + SQLite + Vector Store)

## Goals (MVP)
- Detailed onboarding to "know the user"
- User sends meal/ingredients via **text or photo**
- System classifies input (meal vs ingredients), proposes **healthier options**
- Generates a **recipe** for the chosen option
- User gives feedback (like/dislike, cooked again, tags)
- System **learns**: updates profile + stores retrievable memories (vector store)

Non-goals (MVP): meal plan for the day, grocery list consolidation, precise macros.

---

## High-level Components

### 1) Flutter Web (UI)
- Chat-style interface
- Onboarding questionnaire UI
- Image picker/camera capture (web upload)
- Renders: follow-up questions, suggestions list, recipe output
- Feedback buttons + tags + optional notes

### 2) Local Backend (FastAPI)
- Single source of truth for orchestration and storage
- Handles multipart image upload
- Calls Gemini models (vision + text generation + embeddings)
- Writes/reads from SQLite and vector store
- Exposes REST endpoints to Flutter

### 3) Gemini (API key)
- Vision Agent: interpret image and classify meal vs ingredients
- Suggestion Agent: propose healthier options / meal ideas
- Recipe Agent: generate final recipe JSON
- Embeddings: embed memory facts for retrieval

### 4) Local Storage
- SQLite: profile, meals, feedback, preference facts, memory items
- Filesystem: images
- Vector store (Chroma persistent): embeddings for memory retrieval

---

## Runtime Diagram (conceptual)

Flutter Web
  -> POST /api/user/profile         (onboarding)
  -> POST /api/chat/turn            (text + optional images)
      FastAPI Orchestrator
        -> (if images) Vision Agent (Gemini multimodal)
        -> Suggestion Agent (Gemini text)
        -> store pending suggestions in session_state
  -> POST /api/chat/select          (choose suggestion)
      FastAPI Orchestrator
        -> Recipe Agent (Gemini text)
        -> persist meal in meals
  -> POST /api/feedback             (like/dislike)
      FastAPI Orchestrator
        -> Memory Update Agent (Gemini text)
        -> update preference_facts + memory_items
        -> embed memory_items (Gemini embeddings) -> vector store

---

## Orchestration Details

### Context building (every request)
The orchestrator constructs a compact context bundle:
- Profile summary (diet style, goals, allergies, dislikes, equipment, time, skill)
- Top preference facts (strongest fact_key by strength)
- Recent meals (last 5) with outcomes
- Retrieved memories (vector search topK) for current topic

This context is passed into downstream agents.

### Agent pipeline (MVP)

#### A) Vision Agent (only if images provided)
Input:
- image bytes
- optional user text
Output:
- VisionResult (docs/04-agent-io-schemas.md)
Behavior:
- classify: meal_photo vs ingredients_photo vs unknown
- extract meal name and/or ingredients list
- ask follow-up questions if uncertain

#### B) Suggestion Agent
Input:
- VisionResult or text-only parse
- user context bundle
Output:
- SuggestionsResult
Behavior:
- If meal: 1–3 healthier variations
- If ingredients: 3–5 healthy meal ideas

#### C) Recipe Agent
Input:
- selected suggestion + user context bundle
Output:
- RecipeResult
Behavior:
- step-by-step recipe tailored to skill/equipment/time
- substitutions aligned to dislikes/allergies

#### D) Memory Update Agent (on feedback)
Input:
- meal summary + recipe tags + feedback
- user profile and current preference facts
Output:
- MemoryWriteResult
Behavior:
- writes short memory facts
- outputs preference delta updates
- outputs a profile patch (likes/dislikes additions)

---

## Persistence Model (what is stored)

Stored:
- user_profile (onboarding + updates)
- preference_facts (normalized learned facts with strength)
- meals (final recipe JSON + tags)
- meal_outcomes (liked/disliked/cooked_again + tags/notes)
- memory_items (short facts) + embeddings in vector store
- session_state (ephemeral pending suggestions per session)

Not stored:
- full chat transcript
- raw prompts or chain-of-thought
- large intermediate model outputs beyond required JSON

---

## Local Folder Layout

Root: ./local_data/user_0001/
- images/                # uploaded meal/ingredient photos
- sqlite/app.db          # SQLite database
- vector/                # Chroma persistence
- logs/app.log           # optional structured logs

---

## Key Non-functional Requirements (MVP)
- Deterministic schemas (validate JSON with pydantic)
- Fail-safe: if parsing/validation fails, return follow-up question or safe error
- No secrets in code: Gemini key via env var
- CORS enabled for Flutter Web in local dev
