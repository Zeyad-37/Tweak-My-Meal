"""
SQLite Database Manager with async support
"""
import json
import aiosqlite
from pathlib import Path
from datetime import datetime, timezone
from typing import Optional, Any
from contextlib import asynccontextmanager

from ..config import settings


# DDL from docs/03-data-model.md
DDL = """
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  user_id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  storage_root TEXT NOT NULL
);

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

CREATE TABLE IF NOT EXISTS meals (
  meal_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  title TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  input_text TEXT,
  input_image_paths_json TEXT NOT NULL DEFAULT '[]',
  vision_result_json TEXT,
  suggestion_id TEXT,
  recipe_json TEXT NOT NULL,
  tags_json TEXT NOT NULL DEFAULT '[]',
  generated_image_path TEXT
);

CREATE INDEX IF NOT EXISTS idx_meals_user_created
  ON meals(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS meal_outcomes (
  meal_id TEXT PRIMARY KEY REFERENCES meals(meal_id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  liked INTEGER NOT NULL,
  cooked_again INTEGER NOT NULL,
  tags_json TEXT NOT NULL DEFAULT '[]',
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_outcomes_user_created
  ON meal_outcomes(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS memory_items (
  memory_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  kind TEXT NOT NULL,
  text TEXT NOT NULL,
  salience REAL NOT NULL DEFAULT 0.0,
  source_meal_id TEXT,
  embedding_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_memory_user_salience
  ON memory_items(user_id, salience DESC);

CREATE TABLE IF NOT EXISTS session_state (
  session_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  state_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_session_updated
  ON session_state(updated_at DESC);
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self._connection: Optional[aiosqlite.Connection] = None

    async def connect(self):
        # Ensure parent directories exist
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._connection = await aiosqlite.connect(str(self.db_path))
        self._connection.row_factory = aiosqlite.Row
        # Initialize schema
        await self._connection.executescript(DDL)
        await self._connection.commit()
        
        # Run migrations for existing databases
        await self._run_migrations()

    async def _run_migrations(self):
        """Run migrations for existing databases"""
        try:
            # Add generated_image_path column if it doesn't exist
            await self._connection.execute(
                "ALTER TABLE meals ADD COLUMN generated_image_path TEXT"
            )
            await self._connection.commit()
        except Exception:
            # Column already exists, ignore
            pass

    async def close(self):
        if self._connection:
            await self._connection.close()

    @property
    def conn(self) -> aiosqlite.Connection:
        if not self._connection:
            raise RuntimeError("Database not connected")
        return self._connection

    # ========================================================================
    # User Operations
    # ========================================================================

    async def ensure_user(self, user_id: str) -> str:
        """Create user if not exists, return storage_root"""
        storage_root = str(settings.user_storage_root(user_id))
        
        await self.conn.execute(
            """INSERT OR IGNORE INTO users (user_id, created_at, storage_root)
               VALUES (?, ?, ?)""",
            (user_id, now_iso(), storage_root)
        )
        await self.conn.commit()
        return storage_root

    async def get_user(self, user_id: str) -> Optional[dict]:
        cursor = await self.conn.execute(
            "SELECT * FROM users WHERE user_id = ?", (user_id,)
        )
        row = await cursor.fetchone()
        return dict(row) if row else None

    # ========================================================================
    # Profile Operations
    # ========================================================================

    async def upsert_profile(self, user_id: str, profile: dict) -> int:
        """Upsert profile, return version (always 1 for MVP)"""
        await self.conn.execute(
            """INSERT INTO user_profile (
                user_id, updated_at, display_name, diet_style, goals_json,
                allergies_json, dislikes_json, likes_json, cooking_skill,
                time_per_meal_minutes, budget, household_size, equipment_json,
                units, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                updated_at = excluded.updated_at,
                display_name = excluded.display_name,
                diet_style = excluded.diet_style,
                goals_json = excluded.goals_json,
                allergies_json = excluded.allergies_json,
                dislikes_json = excluded.dislikes_json,
                likes_json = excluded.likes_json,
                cooking_skill = excluded.cooking_skill,
                time_per_meal_minutes = excluded.time_per_meal_minutes,
                budget = excluded.budget,
                household_size = excluded.household_size,
                equipment_json = excluded.equipment_json,
                units = excluded.units,
                notes = excluded.notes
            """,
            (
                user_id,
                now_iso(),
                profile.get("display_name"),
                profile.get("diet_style"),
                json.dumps(profile.get("goals", [])),
                json.dumps(profile.get("allergies", [])),
                json.dumps(profile.get("dislikes", [])),
                json.dumps(profile.get("likes", [])),
                profile.get("cooking_skill"),
                profile.get("time_per_meal_minutes"),
                profile.get("budget"),
                profile.get("household_size"),
                json.dumps(profile.get("equipment", [])),
                profile.get("units", "metric"),
                profile.get("notes"),
            )
        )
        await self.conn.commit()
        return 1

    async def get_profile(self, user_id: str) -> Optional[dict]:
        cursor = await self.conn.execute(
            "SELECT * FROM user_profile WHERE user_id = ?", (user_id,)
        )
        row = await cursor.fetchone()
        if not row:
            return None
        
        data = dict(row)
        # Parse JSON fields
        for field in ["goals_json", "allergies_json", "dislikes_json", "likes_json", "equipment_json"]:
            key = field.replace("_json", "")
            data[key] = json.loads(data.pop(field, "[]"))
        return data

    # ========================================================================
    # Preference Facts
    # ========================================================================

    async def get_top_preference_facts(self, user_id: str, limit: int = 10) -> list[dict]:
        cursor = await self.conn.execute(
            """SELECT fact_key, strength FROM preference_facts
               WHERE user_id = ? ORDER BY strength DESC LIMIT ?""",
            (user_id, limit)
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def update_preference_fact(
        self, user_id: str, fact_key: str, delta: float, source_meal_id: Optional[str] = None
    ):
        await self.conn.execute(
            """INSERT INTO preference_facts (user_id, fact_key, strength, last_updated_at, source_meal_id)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(user_id, fact_key) DO UPDATE SET
                   strength = preference_facts.strength + excluded.strength,
                   last_updated_at = excluded.last_updated_at,
                   source_meal_id = COALESCE(excluded.source_meal_id, preference_facts.source_meal_id)
            """,
            (user_id, fact_key, delta, now_iso(), source_meal_id)
        )
        await self.conn.commit()

    # ========================================================================
    # Meals
    # ========================================================================

    async def create_meal(
        self,
        meal_id: str,
        user_id: str,
        title: str,
        source_kind: str,
        recipe_json: str,
        tags: list[str],
        input_text: Optional[str] = None,
        input_image_paths: list[str] = None,
        vision_result_json: Optional[str] = None,
        suggestion_id: Optional[str] = None,
        generated_image_path: Optional[str] = None,
    ):
        await self.conn.execute(
            """INSERT INTO meals (
                meal_id, user_id, created_at, title, source_kind, input_text,
                input_image_paths_json, vision_result_json, suggestion_id,
                recipe_json, tags_json, generated_image_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                meal_id,
                user_id,
                now_iso(),
                title,
                source_kind,
                input_text,
                json.dumps(input_image_paths or []),
                vision_result_json,
                suggestion_id,
                recipe_json,
                json.dumps(tags),
                generated_image_path,
            )
        )
        await self.conn.commit()

    async def get_meal(self, meal_id: str) -> Optional[dict]:
        cursor = await self.conn.execute(
            "SELECT * FROM meals WHERE meal_id = ?", (meal_id,)
        )
        row = await cursor.fetchone()
        if not row:
            return None
        data = dict(row)
        data["input_image_paths"] = json.loads(data.pop("input_image_paths_json", "[]"))
        data["tags"] = json.loads(data.pop("tags_json", "[]"))
        if data.get("recipe_json"):
            data["recipe"] = json.loads(data["recipe_json"])
        return data

    async def get_recent_meals(self, user_id: str, limit: int = 5) -> list[dict]:
        cursor = await self.conn.execute(
            """SELECT meal_id, title, tags_json, created_at FROM meals
               WHERE user_id = ? ORDER BY created_at DESC LIMIT ?""",
            (user_id, limit)
        )
        rows = await cursor.fetchall()
        result = []
        for r in rows:
            d = dict(r)
            d["tags"] = json.loads(d.pop("tags_json", "[]"))
            result.append(d)
        return result

    # ========================================================================
    # Meal Outcomes
    # ========================================================================

    async def create_outcome(
        self,
        meal_id: str,
        user_id: str,
        liked: bool,
        cooked_again: bool,
        tags: list[str],
        notes: Optional[str] = None,
    ):
        await self.conn.execute(
            """INSERT INTO meal_outcomes (meal_id, user_id, created_at, liked, cooked_again, tags_json, notes)
               VALUES (?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(meal_id) DO UPDATE SET
                   liked = excluded.liked,
                   cooked_again = excluded.cooked_again,
                   tags_json = excluded.tags_json,
                   notes = excluded.notes
            """,
            (meal_id, user_id, now_iso(), int(liked), int(cooked_again), json.dumps(tags), notes)
        )
        await self.conn.commit()

    # ========================================================================
    # Memory Items
    # ========================================================================

    async def create_memory_item(
        self,
        memory_id: str,
        user_id: str,
        kind: str,
        text: str,
        salience: float,
        source_meal_id: Optional[str] = None,
        embedding_id: Optional[str] = None,
    ):
        await self.conn.execute(
            """INSERT INTO memory_items (memory_id, user_id, created_at, kind, text, salience, source_meal_id, embedding_id)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (memory_id, user_id, now_iso(), kind, text, salience, source_meal_id, embedding_id)
        )
        await self.conn.commit()

    async def get_memory_items(self, user_id: str, limit: int = 50) -> list[dict]:
        cursor = await self.conn.execute(
            """SELECT * FROM memory_items WHERE user_id = ? ORDER BY salience DESC LIMIT ?""",
            (user_id, limit)
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    # ========================================================================
    # Session State
    # ========================================================================

    async def get_session_state(self, session_id: str) -> Optional[dict]:
        cursor = await self.conn.execute(
            "SELECT state_json FROM session_state WHERE session_id = ?", (session_id,)
        )
        row = await cursor.fetchone()
        if not row:
            return None
        return json.loads(row["state_json"])

    async def upsert_session_state(self, session_id: str, user_id: str, state: dict):
        await self.conn.execute(
            """INSERT INTO session_state (session_id, user_id, created_at, updated_at, state_json)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(session_id) DO UPDATE SET
                   updated_at = excluded.updated_at,
                   state_json = excluded.state_json
            """,
            (session_id, user_id, now_iso(), now_iso(), json.dumps(state))
        )
        await self.conn.commit()

    async def delete_session_state(self, session_id: str):
        await self.conn.execute(
            "DELETE FROM session_state WHERE session_id = ?", (session_id,)
        )
        await self.conn.commit()

    # ========================================================================
    # History
    # ========================================================================

    async def get_history(self, user_id: str, limit: int = 50, offset: int = 0) -> list[dict]:
        cursor = await self.conn.execute(
            """SELECT m.meal_id, m.created_at, m.title, m.tags_json, m.generated_image_path,
                      o.liked, o.cooked_again, o.tags_json as outcome_tags_json
               FROM meals m
               LEFT JOIN meal_outcomes o ON m.meal_id = o.meal_id
               WHERE m.user_id = ?
               ORDER BY m.created_at DESC
               LIMIT ? OFFSET ?""",
            (user_id, limit, offset)
        )
        rows = await cursor.fetchall()
        result = []
        for r in rows:
            d = dict(r)
            d["tags"] = json.loads(d.pop("tags_json", "[]"))
            d.pop("outcome_tags_json", None)
            d["liked"] = bool(d["liked"]) if d["liked"] is not None else None
            d["cooked_again"] = bool(d["cooked_again"]) if d["cooked_again"] is not None else None
            # Convert local path to URL-friendly format if exists
            if d.get("generated_image_path"):
                d["image_path"] = d["generated_image_path"]
            result.append(d)
        return result


# Global database instance (per user for MVP)
_db_instances: dict[str, Database] = {}


async def get_db(user_id: str = "user_0001") -> Database:
    """Get or create database instance for user"""
    if user_id not in _db_instances:
        db_path = settings.user_db_path(user_id)
        db = Database(db_path)
        await db.connect()
        _db_instances[user_id] = db
    return _db_instances[user_id]
