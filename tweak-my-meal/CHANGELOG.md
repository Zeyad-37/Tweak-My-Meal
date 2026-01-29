# Changelog

All notable changes to the "Tweak My Meal" project will be documented in this file.

## [Unreleased] - 2026-01-29

### Added
- **FastAPI Backend** (`backend/`):
    - Complete REST API matching `docs/02-api-contract.md`
    - SQLite database with schema from `docs/03-data-model.md`
    - Chroma vector store for memory retrieval
    - 5 AI Agents + Orchestrator:
        - `VisionAgent`: Image classification (meal/ingredients) with GPT-4o vision
        - `MealUnderstandingAgent`: Normalizes user input
        - `SuggestionAgent`: Generates healthier meal options
        - `RecipeAgent`: Full recipe generation
        - `MemoryUpdateAgent`: Learning from feedback
    - API Endpoints: `/api/user/profile`, `/api/chat/turn`, `/api/chat/select`, `/api/feedback`, `/api/history`
- **Flutter Chat Screen** (`chat_screen.dart`):
    - Full meal analysis flow with image upload
    - Suggestion selection UI
    - Recipe display with ingredients and steps
    - Feedback (like/dislike) functionality
- **API Client** (`api_client.dart`):
    - HTTP client for backend communication
    - Multipart image upload support
- **Dependencies**:
    - Backend: `fastapi`, `uvicorn`, `openai`, `chromadb`, `aiosqlite`, `pydantic`
    - Flutter: `http`, `http_parser`

### Changed
- **AI Provider**: Migrated from Google Gemini to **OpenAI GPT-4o**
    - Updated `Config` to use `OPEN_AI_KEY` environment variable
    - Created `OpenAIService` for Flutter direct calls (onboarding)
    - Backend uses OpenAI Python SDK for all agent calls
- **Architecture**: Moved from Flutter-direct-to-AI to **Flutter → FastAPI Backend → OpenAI**
- **Onboarding**: Now saves profile to backend and navigates to Chat screen
- **Navigation**: Added `/chat` route for main meal analysis flow

### Documentation
- Added `docs/12-agents-vision-and-flow.md` with complete agent architecture

## [Previous] - 2026-01-29

### Added
- **Project Structure**: Initialized Flutter Web application structure manually.
- **Dependencies**: Added `provider`, `go_router`, `hive`, `google_fonts`, `glass_kit`, `flutter_animate`, `flutter_dotenv`.
- **UI System**:
    - Created "Premium" Dark Mode Theme with Glassmorphism support.
    - Added `GlassContainer` reusable widget.
- **Screens**:
    - `DashboardScreen`: Main hub with current date and history placeholders.
    - `PlannerScreen`: Meal planning interface.
    - `OnboardingChatScreen`: New conversational UI for user profiling.
- **Persistence**:
    - Configured Hive boxes (`user_prefs`, `meals`) for local data storage.
    - Implemented `UserProvider` to manage profile state and parsing.
- **Configuration**:
    - Added `.env` support (via `assets/env`) for secure API Key management.
    - Added `Config` class helper.
- **Documentation**:
    - Added `docs/01-architecture-local.md`
    - Added `docs/02-api-contract.md`
    - Added `docs/03-data-model.md`
    - Added `docs/04-agent-io-schemas.md`
    - Added `docs/11-project-plan.md`

### Changed
- **Branding**: Renamed application from "NutriGuide" to "Tweak My Meal" across all files.
