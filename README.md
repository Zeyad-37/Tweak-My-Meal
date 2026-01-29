# Tweak My Meal - Meal Nutrition Advisor

## Setup

Since this was generated in an environment without the Flutter SDK configured, you need to perform a few steps to run it:

1.  **Install/Locate Flutter SDK**: Ensure `flutter` is in your PATH.
2.  **Initialize Project**:
    Run the following command in this directory to generate the platform-specific files (ios, android, web, etc.) that were skipped:
    ```bash
    flutter create .
    ```
3.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```
4.  **Run**:
    ```bash
    flutter run -d chrome
    ```

## Features Implemented
-   **Onboarding**: User profiling (Name, Cooking Level).
-   **Dashboard**:
    -   Meal Analysis (Mock AI): Type any meal to get a healthier suggestion.
    -   History: Locally stored session history.
-   **Planner**: simple Daily Meal Plan generator.
-   **Design**: Premium "Glassmorphism" Dark UI.

## Notes
-   **AI Service**: Currently uses `MockAiService` in `lib/services/ai_service.dart`. Connect your real API Key there.
-   **Persistence**: Uses `Hive`.
