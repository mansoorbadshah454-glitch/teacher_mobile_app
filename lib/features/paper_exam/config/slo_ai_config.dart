class SloAiConfig {
  /// Default/Fallback Gemini API Key.
  /// Note: The app automatically fetches the live Master Key & AI config from Firestore
  /// (`curriculums/ai_settings`, `system_config/ai_settings`, `system_configs/global`).
  static const String fallbackGeminiApiKey = "YOUR_GEMINI_API_KEY_HERE";

  /// Primary default Gemini model (Verified fastest & most reliable Vision/OCR Flash model)
  static const String geminiModel = "gemini-3.5-flash-lite";

  /// Prioritized fallback model list ordered by verified live response speed & reliability
  static const List<String> defaultCandidateModels = [
    "gemini-3.5-flash-lite",
    "gemini-3.5-flash",
    "gemini-3.1-flash-lite",
    "gemini-flash-lite-latest",
    "gemini-3.8-flash",
    "gemini-3.7-flash",
    "gemini-3.6-flash",
    "gemini-flash-latest",
    "gemini-2.5-flash",
    "gemini-2.0-flash",
  ];

  /// 30-Second cooldown lock duration to prevent accidental double-tap or spam
  static const Duration generationCooldown = Duration(seconds: 30);
}
