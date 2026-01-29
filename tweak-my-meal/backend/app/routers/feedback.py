"""
Feedback API Routes
"""
from fastapi import APIRouter

from ..schemas.api import ApiResponse, FeedbackRequest, FeedbackResponse
from ..services.orchestrator import Orchestrator
from ..db import get_db

router = APIRouter(prefix="/api", tags=["feedback"])


@router.post("/feedback", response_model=ApiResponse)
async def submit_feedback(request: FeedbackRequest):
    """
    Submit feedback for a meal (like/dislike, cooked again, tags, notes).
    Triggers learning pipeline.
    """
    try:
        # Ensure user exists
        db = await get_db(request.user_id)
        await db.ensure_user(request.user_id)
        
        # Create orchestrator
        orchestrator = Orchestrator(request.user_id)
        
        # Process feedback
        result = await orchestrator.process_feedback(
            meal_id=request.meal_id,
            liked=request.liked,
            cooked_again=request.cooked_again,
            tags=request.tags,
            notes=request.notes,
        )
        
        return ApiResponse.success(FeedbackResponse(
            updated_profile_summary=result["updated_profile_summary"],
            memory_items_written=result["memory_items_written"],
            preference_facts_updated=result["preference_facts_updated"],
        ))
        
    except ValueError as e:
        return ApiResponse.failure("NOT_FOUND", str(e))
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))
