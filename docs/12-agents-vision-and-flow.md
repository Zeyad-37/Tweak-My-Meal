# FILE: docs/12-agents-vision-and-flow.md

# AI Agents Architecture — Vision + Flow (MVP)

## Objectives
- Convert user input (text/photo) into structured understanding
- Propose healthier options aligned to user profile + learned preferences
- Generate a tailored recipe
- Learn from outcomes (like/dislike, cooked again) and improve next time
- Store only useful data (profile facts, meals, outcomes, memory facts)

---

## Agent Roles (MVP)

### 0) Orchestrator (Coach)
Not an LLM agent. Deterministic code that:
- Maintains session state (pending suggestions, clarification state)
- Builds context (profile + facts + retrieved memories)
- Calls LLM agents in a strict pipeline
- Validates agent outputs against schemas
- Persists meals/outcomes/memories and updates preference facts

Inputs:
- user_id, session_id, text, images[], mode_hint
Outputs:
- Follow-up questions OR Suggestions OR Recipe

---

### 1) Vision Agent (Gemini multimodal)
Purpose:
- Interpret images and classify the input as:
  - meal_photo
  - ingredients_photo
  - unknown
- Extract normalized entities:
  - meal name (if meal)
  - ingredient list (if ingredients or visible components)

Input:
- image bytes (1..N)
- optional user text
- minimal hard constraints from profile (allergies, dislikes) to avoid suggesting those as "detected ingredients" unless clearly present

Output: VisionResult (canonical schema)
- kind
- confidence
- detected.meal_name OR detected.ingredients
- follow_up_questions if uncertain

Key behavior:
- If uncertain between meal vs ingredients, choose unknown and ask:
  - "Is this a photo of the prepared meal or ingredients to cook with?"
- If ingredients photo but text indicates it's a meal, include note and ask a clarification question.

---

### 2) Meal Understanding Agent (Text Normalizer)
Purpose:
- Normalize the user input (text-only OR post-vision result) into a common internal representation.
- Decide whether the user wants:
  - healthier version of a meal
  - meal ideas from ingredients
- Extract constraints explicitly stated in the text (time, equipment, preferences)

Input:
- text
- optional VisionResult
- session context (previous follow-up answers)

Output (internal normalized object, not necessarily persisted):
- input_kind: text_meal | text_ingredients | meal_photo | ingredients_photo | unknown
- entities:
  - meal_name (nullable)
  - ingredients[] (nullable)
- constraints:
  - max_time_minutes (nullable)
  - equipment_overrides[] (nullable)
- missing_info_questions[] (if required)

Notes:
- This can be an LLM agent or deterministic heuristics. MVP: LLM optional; heuristics acceptable.
- If VisionResult is confident, this agent is mostly a mapper.

---

### 3) Suggestion Agent (Health Options Generator)
Purpose:
- Produce high-level options WITHOUT full recipes:
  - For meal inputs: 1–3 healthier variations of the same meal
  - For ingredients inputs: 3–5 healthy meal ideas using those ingredients
- Respect user constraints and learned preferences.

Input:
- normalized input (meal_name or ingredients[])
- user context bundle:
  - profile summary
  - top preference facts
  - retrieved memory facts (vector search)
  - equipment/time constraints

Output: SuggestionsResult (canonical schema)
- suggestions[] (each has suggestion_id, title, summary, rationale, tags, time, difficulty)
- follow_up_questions[] if needed

Quality rules:
- Must not suggest allergens or strong dislikes.
- Prefer suggestions matching cooking skill and equipment.
- Keep suggestions concrete enough for selection (e.g., "Air-fryer chicken fajita bowl with extra veg").

---

### 4) Recipe Agent (Full Recipe Generator)
Purpose:
- Convert a selected suggestion into a full recipe:
  - ingredient list with quantities (metric)
  - steps tailored to skill
  - substitutions
  - equipment list
  - warnings (e.g., "contains dairy" if relevant)
  - macros optional later (nullable)

Input:
- selected suggestion (suggestion_id) + suggestion summary/tags
- normalized input
- user context bundle (profile, preferences, memories)

Output: RecipeResult (canonical schema)

Quality rules:
- Must be cookable and coherent (no missing steps)
- Must adapt to:
  - time_per_meal
  - cooking_skill
  - equipment
- Must avoid allergens/dislikes and use substitutes when needed

---

### 5) Memory Update Agent (Learning)
Purpose:
- After feedback, generate:
  - memory_items: short facts suitable for retrieval
  - preference_facts deltas: normalized keys + strength adjustments
  - optional profile_patch (add likes/dislikes explicitly if strongly inferred)

Input:
- meal summary (selected suggestion + recipe tags)
- outcome: liked/disliked, cooked_again, tags, notes
- current top preference facts
- (optional) user profile

Output: MemoryWriteResult (canonical schema)

Learning rules:
- liked = strengthen patterns present in meal (tags: cuisine, spicy, quick, high-protein, cooking method)
- disliked = create avoid facts (e.g., avoid:creamy_sauces) and reduce similar pattern strengths
- cooked_again = strong positive boost for the meal’s pattern tags
- if user wrote explicit preference in notes ("I hate mushrooms"), add to profile_patch.dislikes_add

---

## Flow (End-to-End)

### A) Image path: photo input -> suggestions -> recipe -> feedback -> learning
1. UI: user uploads image (+ optional text)
2. Orchestrator:
   - saves image to local filesystem
   - loads profile + top facts + vector memories
3. Vision Agent:
   - returns VisionResult(kind, detected, questions)
4. If VisionResult.follow_up_questions present and kind == unknown:
   - backend returns Follow-up response (blocking)
5. Else:
   - Meal Understanding Agent normalizes to internal input
   - Suggestion Agent returns SuggestionsResult
   - Orchestrator stores pending suggestions in session_state
   - backend returns Suggestions response
6. UI: user selects a suggestion
7. Orchestrator calls Recipe Agent
8. Orchestrator persists:
   - meals (recipe_json, tags)
9. UI: user likes/dislikes and optionally sets cooked_again later
10. Orchestrator calls Memory Update Agent
11. Orchestrator persists:
   - meal_outcomes
   - memory_items (+ embeddings into vector store)
   - preference_facts updates
   - profile_patch applied

### B) Text-only path: text input -> suggestions -> recipe (same)
- Skip Vision Agent; Meal Understanding Agent classifies as meal vs ingredients from text.

---

## Session State (minimal)
Stored per session_id in session_state.state_json:
- step: "awaiting_followup" | "awaiting_selection" | "done"
- last_input_kind
- vision_result (optional)
- suggestions[] (id, title, tags, summary)
- user_answers to follow-up questions (map)

No full transcript storage.

---

## Context Bundle (what the Orchestrator passes to LLM agents)

### Hard constraints (must-follow)
- allergies[]
- dislikes[]
- diet_style
- equipment[]
- metric units
- time_per_meal_minutes
- cooking_skill

### Soft constraints (preference-guiding)
- top preference_facts (fact_key + strength)
- retrieved memory_items.text (topK vector search)
- recent successful meals (titles + tags)

---

## Output Gating (anti-hallucination measures)
- Validate every agent output with pydantic schema.
- If invalid JSON:
  - retry once with a "repair to valid JSON" prompt
  - if still invalid, return MODEL_ERROR with a user-friendly message
- If a suggestion/recipe includes an allergen/dislike:
  - reject and regenerate with an explicit constraint reminder
- If VisionResult.kind == unknown and confidence < threshold:
  - always return follow-up questions (no guessing)

---

## Practical Defaults (MVP)
- topK vector memories: 5
- recent meals in context: last 5
- top preference facts in context: top 10
- session_state TTL: 24h
- suggestion count:
  - meal: 3
  - ingredients: 5
