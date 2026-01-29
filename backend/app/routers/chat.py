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
