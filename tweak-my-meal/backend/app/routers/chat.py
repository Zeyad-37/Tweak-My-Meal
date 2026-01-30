"""
Chat API Routes - Main interaction endpoints
"""
import json
from typing import Optional, List
from fastapi import APIRouter, HTTPException, UploadFile, File, Form

from ..schemas.api import (
    ApiResponse, ChatTurnRequest, ChatSelectRequest,
    FollowUpResponse, SuggestionsResponse, RecipeResponse,
    ClientContext
)
from ..services.orchestrator import Orchestrator
from ..db import get_db

router = APIRouter(prefix="/api/chat", tags=["chat"])


@router.post("/turn", response_model=ApiResponse)
async def chat_turn(
    user_id: str = Form(default="user_0001"),
    session_id: str = Form(...),
    text: Optional[str] = Form(default=None),
    mode_hint: str = Form(default="auto"),
    client_context: Optional[str] = Form(default=None),
    images: List[UploadFile] = File(default=[]),
):
    """
    Process a chat turn. Accepts text and/or images.
    
    Returns one of:
    - follow_up: Questions to clarify input
    - suggestions: Meal suggestions to choose from
    """
    try:
        # Ensure user exists
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        # Parse client context
        ctx = None
        if client_context:
            try:
                ctx_data = json.loads(client_context)
                ctx = ClientContext.model_validate(ctx_data)
            except Exception:
                pass
        
        # Create orchestrator
        orchestrator = Orchestrator(user_id)
        
        # Save uploaded images
        image_paths = []
        if images:
            image_data = []
            for img in images:
                content = await img.read()
                if content:
                    image_data.append((img.filename or "image.jpg", content))
            
            if image_data:
                image_paths = await orchestrator.save_uploaded_images(image_data)
        
        # Process turn
        result = await orchestrator.process_chat_turn(
            session_id=session_id,
            text=text,
            image_paths=image_paths if image_paths else None,
            mode_hint=mode_hint,
            client_context=ctx.model_dump() if ctx else None,
        )
        
        return ApiResponse.success(result)
        
    except ValueError as e:
        return ApiResponse.failure("VALIDATION_ERROR", str(e))
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


@router.post("/turn/json", response_model=ApiResponse)
async def chat_turn_json(request: ChatTurnRequest):
    """
    Process a text-only chat turn (JSON body).
    """
    try:
        # Ensure user exists
        db = await get_db(request.user_id)
        await db.ensure_user(request.user_id)
        
        # Create orchestrator
        orchestrator = Orchestrator(request.user_id)
        
        # Process turn
        result = await orchestrator.process_chat_turn(
            session_id=request.session_id,
            text=request.text,
            image_paths=None,
            mode_hint=request.mode_hint,
            client_context=request.client_context.model_dump() if request.client_context else None,
        )
        
        return ApiResponse.success(result)
        
    except ValueError as e:
        return ApiResponse.failure("VALIDATION_ERROR", str(e))
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


@router.post("/select", response_model=ApiResponse)
async def chat_select(request: ChatSelectRequest):
    """
    Select a suggestion and generate full recipe.
    """
    try:
        # Ensure user exists
        db = await get_db(request.user_id)
        await db.ensure_user(request.user_id)
        
        # Create orchestrator
        orchestrator = Orchestrator(request.user_id)
        
        # Process selection
        result = await orchestrator.process_selection(
            session_id=request.session_id,
            suggestion_id=request.suggestion_id,
        )
        
        return ApiResponse.success(result)
        
    except ValueError as e:
        return ApiResponse.failure("VALIDATION_ERROR", str(e))
    except Exception as e:
        return ApiResponse.failure("MODEL_ERROR", str(e))


@router.get("/images/{session_id}", response_model=ApiResponse)
async def get_suggestion_images(
    session_id: str,
    user_id: str = "user_0001",
):
    """
    Get generated images for suggestions in a session.
    Frontend can poll this while images are generating.
    """
    try:
        db = await get_db(user_id)
        state = await db.get_session_state(session_id)
        
        if not state:
            return ApiResponse.failure("NOT_FOUND", "Session not found")
        
        suggestion_images = state.get("suggestion_images", {})
        suggestions = state.get("suggestions", [])
        
        return ApiResponse.success({
            "images": suggestion_images,
            "total_suggestions": len(suggestions),
            "images_ready": len(suggestion_images),
            "all_ready": len(suggestion_images) >= len(suggestions) if suggestions else False,
        })
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))


@router.post("/modify", response_model=ApiResponse)
async def chat_modify(
    user_id: str = Form(default="user_0001"),
    session_id: str = Form(...),
    modification: str = Form(...),
):
    """
    Modify the current meal analysis with additional ingredients/preferences.
    Regenerates suggestions using the existing session context plus the modification.
    """
    try:
        # Ensure user exists
        db = await get_db(user_id)
        await db.ensure_user(user_id)
        
        # Create orchestrator
        orchestrator = Orchestrator(user_id)
        
        # Process modification
        result = await orchestrator.process_modification(
            session_id=session_id,
            modification=modification,
        )
        
        return ApiResponse.success(result)
        
    except ValueError as e:
        return ApiResponse.failure("VALIDATION_ERROR", str(e))
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))
