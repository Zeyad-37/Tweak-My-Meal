"""
Tweak My Meal - FastAPI Backend
Main application entry point
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .routers import user_router, chat_router, feedback_router, history_router

# Create app
app = FastAPI(
    title="Tweak My Meal API",
    description="AI-powered nutrition advisor backend",
    version="1.0.0",
)

# CORS for Flutter Web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to your domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(user_router)
app.include_router(chat_router)
app.include_router(feedback_router)
app.include_router(history_router)


@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "ok": True,
        "service": "Tweak My Meal API",
        "version": "1.0.0",
    }


@app.get("/health")
async def health():
    """Health check for monitoring"""
    return {"status": "healthy"}


# Run with: uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=True,
    )
