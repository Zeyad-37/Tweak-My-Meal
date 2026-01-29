# FILE: docs/03-data-model.md

# Data Model (SQLite + Local Files) — MVP

Storage root: ./local_data/user_0001/

- Images: ./local_data/user_0001/images/<uuid>.<ext>
- SQLite: ./local_data/user_0001/sqlite/app.db
- Vector store: ./local_data/user_0001/vector/

## SQLite DDL

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- Single user for MVP (user_0001). Keep table anyway for future multi-user.
CREATE TABLE IF NOT EXISTS users (
  user_id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  storage_root TEXT NOT NULL
);

-- Profile as structured columns + some JSON for flexibility.
CREATE TABLE IF NOT EXISTS user_profile (
  user_id TEXT PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
  updated_at TEXT NOT NULL,
  display_name TEXT,
  diet_style TEXT,
  goals_json TEXT NOT NULL DEFAULT '[]',
  allergies_json TEXT NOT NULL DEFAULT '[]',
  dislikes_json TEXT NOT NULL DEFAULT '[]',
  likes_json TEXT NOT NULL DEFAULT '[]',
  cooking_skill TEXT,
  time_per_meal_minutes INTEGER,
  budget TEXT,
  household_size INTEGER,
  equipment_json TEXT NOT NULL DEFAULT '[]',
  units TEXT NOT NULL DEFAULT 'metric',
  notes TEXT
);

-- Facts derived over time (learning). fact_key is normalized.
CREATE TABLE IF NOT EXISTS preference_facts (
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  fact_key TEXT NOT NULL,
  strength REAL NOT NULL DEFAULT 0.0,
  last_updated_at TEXT NOT NULL,
  source_meal_id TEXT,
  PRIMARY KEY (user_id, fact_key)
);

CREATE INDEX IF NOT EXISTS idx_preference_facts_strength
  ON preference_facts(user_id, strength DESC);

-- Meals generated and/or cooked.
CREATE TABLE IF NOT EXISTS meals (
  meal_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  title TEXT NOT NULL,
  source_kind TEXT NOT NULL, -- meal_photo|ingredients_photo|text_meal|text_ingredients
  input_text TEXT,
  input_image_paths_json TEXT NOT NULL DEFAULT '[]',
  vision_result_json TEXT,
  suggestion_id TEXT,
  recipe_json TEXT NOT NULL,
  tags_json TEXT NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_meals_user_created
  ON meals(user_id, created_at DESC);

-- Outcome/feedback for a meal.
CREATE TABLE IF NOT EXISTS meal_outcomes (
  meal_id TEXT PRIMARY KEY REFERENCES meals(meal_id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  liked INTEGER NOT NULL,         -- 0/1
  cooked_again INTEGER NOT NULL,  -- 0/1
  tags_json TEXT NOT NULL DEFAULT '[]',
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_outcomes_user_created
  ON meal_outcomes(user_id, created_at DESC);

-- Memory items that get embedded and retrieved (short facts).
CREATE TABLE IF NOT EXISTS memory_items (
  memory_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  kind TEXT NOT NULL,        -- like|dislike|constraint|pattern
  text TEXT NOT NULL,
  salience REAL NOT NULL DEFAULT 0.0,
  source_meal_id TEXT,
  embedding_id TEXT          -- key used by vector store (if needed)
);

CREATE INDEX IF NOT EXISTS idx_memory_user_salience
  ON memory_items(user_id, salience DESC);

-- Session state: ephemeral chat flow state (pending suggestions, etc.)
-- Backend may prune rows older than N hours.
CREATE TABLE IF NOT EXISTS session_state (
  session_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  state_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_session_updated
  ON session_state(updated_at DESC);
