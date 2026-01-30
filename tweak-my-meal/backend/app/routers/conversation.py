"""
Conversation/Chat History API Routes
"""
import json
import uuid
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter
from pydantic import BaseModel

from ..schemas.api import ApiResponse
from ..db import get_db
from ..services.openai_client import openai_client

router = APIRouter(prefix="/api/conversation", tags=["conversation"])


class ChatMessage(BaseModel):
    role: str  # 'user' or 'assistant'
    content: str
    timestamp: Optional[str] = None


class SendMessageRequest(BaseModel):
    user_id: str = "user_0001"
    message: str


class ChatHistoryResponse(BaseModel):
    messages: list[dict]
    has_profile: bool
    display_name: Optional[str] = None


# System prompt for the conversational agent
CHAT_SYSTEM_PROMPT = """You are a friendly nutrition assistant for "Tweak My Meal" app.

Your role:
1. Get to know the user - ask for their name, dietary preferences, allergies, goals
2. Remember everything they tell you and help them eat healthier
3. Be conversational, warm, and encouraging
4. Keep responses concise (2-3 sentences usually)

If this is a new user (no name known), introduce yourself and ask for their name.
If they share preferences (likes, dislikes, allergies), acknowledge and remember them.

When user shares a preference like "I don't like avocado" or "I'm allergic to nuts":
- Acknowledge it warmly
- Include a JSON block at the END of your response to update their profile:
```json
{"profile_update": {"dislikes_add": ["avocado"]}}
```
or
```json
{"profile_update": {"allergies_add": ["nuts"]}}
```
or for likes:
```json
{"profile_update": {"likes_add": ["spicy food"]}}
```
or for name:
```json
{"profile_update": {"display_name": "John"}}
```
or for goals:
```json
{"profile_update": {"goals_add": ["lose weight"]}}
```

Only include the JSON block when there's an actual preference to save. The JSON must be valid.
"""


@router.get("/history", response_model=ApiResponse)
async def get_chat_history(user_id: str = "user_0001"):
    """
    Get chat history for user.
    """
    try:
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        # Get profile info
        profile = await db.get_profile(user_id)
        has_profile = profile is not None and bool(profile.get("display_name"))
        display_name = profile.get("display_name") if profile else None
        
        # Get chat history from session state (we'll use a special session for persistent chat)
        chat_state = await db.get_session_state(f"chat_{user_id}")
        messages = chat_state.get("messages", []) if chat_state else []
        
        return ApiResponse.success({
            "messages": messages,
            "has_profile": has_profile,
            "display_name": display_name,
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


@router.post("/send", response_model=ApiResponse)
async def send_message(request: SendMessageRequest):
    """
    Send a message to the chat agent.
    Returns agent response and any profile updates.
    """
    try:
        db = await get_db(request.user_id)
        await db.ensure_user(request.user_id)
        
        # Get existing chat history
        chat_state = await db.get_session_state(f"chat_{request.user_id}")
        messages = chat_state.get("messages", []) if chat_state else []
        
        # Get profile for context
        profile = await db.get_profile(request.user_id)
        pref_facts = await db.get_top_preference_facts(request.user_id, limit=10)
        
        # Build context for AI
        context = _build_user_context(profile, pref_facts)
        
        # Add user message to history
        user_msg = {
            "role": "user",
            "content": request.message,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        messages.append(user_msg)
        
        # Prepare messages for OpenAI
        ai_messages = [{"role": "system", "content": CHAT_SYSTEM_PROMPT + "\n\n" + context}]
        
        # Add conversation history (last 20 messages to stay within context)
        for msg in messages[-20:]:
            ai_messages.append({"role": msg["role"], "content": msg["content"]})
        
        # Get AI response
        response = await openai_client.chat(
            messages=ai_messages,
            temperature=0.7,
            max_tokens=500,
        )
        
        # Parse response for profile updates
        profile_update, clean_response = _extract_profile_update(response)
        
        # Apply profile updates if any
        profile_changed = False
        if profile_update:
            profile_changed = await _apply_profile_update(db, request.user_id, profile, profile_update)
        
        # Add assistant message to history
        assistant_msg = {
            "role": "assistant",
            "content": clean_response,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        messages.append(assistant_msg)
        
        # Save updated chat history
        await db.upsert_session_state(f"chat_{request.user_id}", request.user_id, {
            "messages": messages,
        })
        
        # Get updated profile if changed
        updated_profile = None
        if profile_changed:
            updated_profile = await db.get_profile(request.user_id)
        
        return ApiResponse.success({
            "message": assistant_msg,
            "profile_changed": profile_changed,
            "updated_profile": {
                "display_name": updated_profile.get("display_name") if updated_profile else None,
                "allergies": updated_profile.get("allergies", []) if updated_profile else [],
                "dislikes": updated_profile.get("dislikes", []) if updated_profile else [],
                "likes": updated_profile.get("likes", []) if updated_profile else [],
                "goals": updated_profile.get("goals", []) if updated_profile else [],
            } if updated_profile else None,
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


@router.post("/clear", response_model=ApiResponse)
async def clear_chat_history(user_id: str = "user_0001"):
    """
    Clear chat history (but keep profile).
    """
    try:
        db = await get_db(user_id)
        await db.delete_session_state(f"chat_{user_id}")
        
        return ApiResponse.success({"cleared": True})
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


def _build_user_context(profile: dict | None, pref_facts: list[dict]) -> str:
    """Build context string from user profile."""
    parts = ["Current user context:"]
    
    if profile:
        if profile.get("display_name"):
            parts.append(f"- Name: {profile['display_name']}")
        if profile.get("allergies"):
            parts.append(f"- Allergies: {', '.join(profile['allergies'])}")
        if profile.get("dislikes"):
            parts.append(f"- Dislikes: {', '.join(profile['dislikes'])}")
        if profile.get("likes"):
            parts.append(f"- Likes: {', '.join(profile['likes'])}")
        if profile.get("goals"):
            parts.append(f"- Goals: {', '.join(profile['goals'])}")
        if profile.get("diet_style"):
            parts.append(f"- Diet: {profile['diet_style']}")
        if profile.get("cooking_skill"):
            parts.append(f"- Cooking skill: {profile['cooking_skill']}")
    else:
        parts.append("- New user, no profile yet")
    
    if pref_facts:
        learned = [f["fact_key"] for f in pref_facts[:5]]
        parts.append(f"- Learned preferences: {', '.join(learned)}")
    
    return "\n".join(parts)


def _extract_profile_update(response: str) -> tuple[dict | None, str]:
    """Extract profile update JSON from response and return clean text."""
    import re
    
    # Look for JSON block
    json_pattern = r'```json\s*(\{[^`]+\})\s*```'
    match = re.search(json_pattern, response)
    
    if match:
        try:
            json_str = match.group(1)
            data = json.loads(json_str)
            profile_update = data.get("profile_update")
            
            # Remove JSON block from response
            clean_response = re.sub(json_pattern, '', response).strip()
            
            return profile_update, clean_response
        except json.JSONDecodeError:
            pass
    
    return None, response


async def _apply_profile_update(db, user_id: str, current_profile: dict | None, update: dict) -> bool:
    """Apply profile updates and return True if profile changed."""
    if not update:
        return False
    
    profile = current_profile or {}
    changed = False
    
    # Handle display_name
    if "display_name" in update:
        profile["display_name"] = update["display_name"]
        changed = True
    
    # Handle list additions
    for key in ["likes_add", "dislikes_add", "allergies_add", "goals_add"]:
        if key in update:
            base_key = key.replace("_add", "")
            if base_key == "likes":
                base_key = "likes"
            elif base_key == "goals":
                base_key = "goals"
            
            current_list = profile.get(base_key, [])
            new_items = update[key] if isinstance(update[key], list) else [update[key]]
            
            for item in new_items:
                if item not in current_list:
                    current_list.append(item)
                    changed = True
            
            profile[base_key] = current_list
    
    # Handle diet_style, cooking_skill
    for key in ["diet_style", "cooking_skill"]:
        if key in update:
            profile[key] = update[key]
            changed = True
    
    if changed:
        await db.upsert_profile(user_id, profile)
    
    return changed
