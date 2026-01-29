# FILE: docs/11-project-plan.md

# Project Plan (Hackathon MVP) — Milestones, Tasks, Deliverables

## Team split (suggested)
- Backend/AI Orchestrator (FastAPI + Gemini + storage)
- Flutter Web UI (chat + onboarding + render results)
- Prompting/Validation (schemas, tests, goldens)

---

## Milestone 0 — Repo + Docs baseline (0.5 day)
### Deliverables
- docs folder committed (contracts + schemas + architecture + plan)
- env var conventions documented
- local run commands written

### Tasks
- [ ] Create docs/ directory with:
  - [ ] docs/01-architecture-local.md
  - [ ] docs/02-api-contract.md
  - [ ] docs/03-data-model.md
  - [ ] docs/04-agent-io-schemas.md
  - [ ] docs/06-onboarding-questionnaire.md (if not already)
- [ ] Add .env.example (GEMINI_API_KEY, model names, ports)
- [ ] Define “golden demo script” in docs/10-test-plan.md

---

## Milestone 1 — Backend skeleton + persistence (0.5–1 day)
### Deliverables
- FastAPI server runs locally
- SQLite initialized automatically
- Local user folder created
- Health endpoints working

### Tasks
- [ ] FastAPI scaffold:
  - [ ] project structure (app/, routers/, services/, db/)
  - [ ] CORS for Flutter Web
  - [ ] response envelope helper (ok/data, ok/error)
- [ ] Storage bootstrap:
  - [ ] create ./local_data/user_0001/ subfolders
  - [ ] initialize SQLite (execute DDL from docs/03-data-model.md)
- [ ] Implement endpoint:
  - [ ] POST /api/user/profile (upsert profile, return summary)
  - [ ] GET /api/user/summary (profile + top facts)

Acceptance checks:
- [ ] POST profile creates DB + returns ok
- [ ] GET summary returns profile_summary and empty preferences

---

## Milestone 2 — Gemini integration (Vision + Text) (0.5–1 day)
### Deliverables
- Working Gemini client with API key
- Vision agent returns VisionResult schema (validated)
- Suggestion agent returns SuggestionsResult schema (validated)

### Tasks
- [ ] Add Gemini SDK dependency (python-genai) and client wrapper
- [ ] Implement “strict JSON” response parsing:
  - [ ] attempt JSON parse
  - [ ] if invalid, retry once with repair prompt
  - [ ] if still invalid, return MODEL_ERROR
- [ ] Implement Vision Agent:
  - [ ] input: image bytes + optional text
  - [ ] output: VisionResult
- [ ] Implement Suggestion Agent:
  - [ ] input: VisionResult or text
  - [ ] output: SuggestionsResult

Acceptance checks:
- [ ] Upload an image → returns suggestions without crashing
- [ ] Text-only “I ate a burger” → returns meal suggestions

---

## Milestone 3 — Chat endpoints + session state (1 day)
### Deliverables
- /api/chat/turn accepts multipart and returns follow-up or suggestions
- /api/chat/select generates a recipe and persists a meal
- session_state supports pending suggestions per session_id

### Tasks
- [ ] Implement POST /api/chat/turn:
  - [ ] accept JSON or multipart
  - [ ] store uploaded images to ./local_data/user_0001/images/
  - [ ] run Vision Agent when images exist
  - [ ] run Suggestion Agent
  - [ ] persist session_state with suggestion list keyed by session_id
- [ ] Implement POST /api/chat/select:
  - [ ] read session_state, validate suggestion_id
  - [ ] call Recipe Agent to produce RecipeResult
  - [ ] persist meals row with recipe_json + tags_json
  - [ ] return { kind: recipe, meal_id, recipe }
- [ ] Implement Recipe Agent:
  - [ ] input: suggestion + user context bundle
  - [ ] output: RecipeResult JSON

Acceptance checks:
- [ ] Full flow: image → suggestions → select → recipe returned and stored

---

## Milestone 4 — Feedback + learning (0.5–1 day)
### Deliverables
- Feedback stored
- Profile updates over time (preference_facts + optional profile_patch)
- Memory items embedded and retrievable

### Tasks
- [ ] Implement POST /api/feedback:
  - [ ] write meal_outcomes row
  - [ ] call Memory Update Agent -> MemoryWriteResult
  - [ ] apply profile_patch to user_profile (append-only where possible)
  - [ ] upsert preference_facts (strength += delta)
  - [ ] insert memory_items
- [ ] Vector store integration (Chroma persistent):
  - [ ] embed memory_items.text using gemini-embedding-001
  - [ ] persist embedding vectors in Chroma under ./local_data/user_0001/vector/
- [ ] Retrieval integration:
  - [ ] on /api/chat/turn and /api/chat/select, perform similarity search topK=5
  - [ ] include retrieved memory texts in agent context

Acceptance checks:
- [ ] Like/dislike changes preference facts
- [ ] Second request shows personalization (e.g., avoids disliked patterns)

---

## Milestone 5 — Flutter Web UI (in parallel) (1–2 days)
### Deliverables
- Onboarding wizard → saves profile
- Chat UI:
  - sends text
  - sends images (multipart)
  - renders follow-up questions, suggestions, recipe
- Feedback UI: like/dislike + cooked_again + tags + notes
- History view (minimal)

### Tasks
- [ ] Onboarding screen:
  - [ ] diet style, goals, allergies, dislikes, likes, skill, time, equipment
  - [ ] submit to POST /api/user/profile
- [ ] Chat screen:
  - [ ] message list + input box
  - [ ] image picker (web) and upload via multipart to /api/chat/turn
  - [ ] render response types:
    - [ ] follow_up -> show questions as assistant messages
    - [ ] suggestions -> show selectable cards/buttons
    - [ ] recipe -> show ingredients + steps
- [ ] Selection action:
  - [ ] call POST /api/chat/select
- [ ] Feedback widget:
  - [ ] POST /api/feedback
- [ ] History:
  - [ ] GET /api/history, render list of liked/disliked meals

Acceptance checks:
- [ ] Demo-ready UI: onboarding + one full flow + feedback

---

## Milestone 6 — Hardening + demo polish (0.5 day)
### Deliverables
- Reliable responses and clearer errors
- Quick demo script
- Basic regression tests for schema validity

### Tasks
- [ ] Add pydantic models for all schemas and validate every model output
- [ ] Add structured logging (request_id, session_id)
- [ ] Add “golden” prompt tests (optional but recommended):
  - [ ] store 3 inputs and snapshot expected schema fields (not exact text)
- [ ] Improve UI:
  - [ ] loading states
  - [ ] retry on MODEL_ERROR
  - [ ] show “what we learned” snippet (top preferences)

Acceptance checks:
- [ ] Run demo twice; second run reflects learned preferences

---

## Critical path (if time is short)
1) Backend Milestone 1 + 2 + 3 (end-to-end functionality)
2) Flutter basic chat + image upload + render recipe
3) Feedback updates + simple preference facts (vector store can be added last)

---

## Definition of Done (MVP)
- Onboarding stored
- Image meal → suggestions → recipe
- Like/dislike stored
- Second run uses learned facts/memories (observable change)
- Everything runs locally with Gemini API key via env var
