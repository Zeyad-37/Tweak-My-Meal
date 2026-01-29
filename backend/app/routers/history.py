"""
History API Routes
"""
from fastapi import APIRouter

from ..schemas.api import ApiResponse, HistoryResponse, HistoryItem
from ..db import get_db

router = APIRouter(prefix="/api", tags=["history"])


@router.get("/history", response_model=ApiResponse)
async def get_history(
    user_id: str = "user_0001",
    limit: int = 50,
    offset: int = 0,
):
    """
    Get meal history for user.
    """
    try:
        db = await get_db(user_id)
        
        # Check user exists
        user = await db.get_user(user_id)
        if not user:
            return ApiResponse.failure("NOT_FOUND", f"User {user_id} not found")
        
        # Get history
        items = await db.get_history(user_id, limit=limit, offset=offset)
        
        return ApiResponse.success(HistoryResponse(
            items=[
                HistoryItem(
                    meal_id=item["meal_id"],
                    created_at=item["created_at"],
                    title=item["title"],
                    liked=item.get("liked"),
                    cooked_again=item.get("cooked_again"),
                    tags=item.get("tags", []),
                )
                for item in items
            ],
            limit=limit,
            offset=offset,
        ))
        
    except Exception as e:
        return ApiResponse.failure("INTERNAL_ERROR", str(e))
