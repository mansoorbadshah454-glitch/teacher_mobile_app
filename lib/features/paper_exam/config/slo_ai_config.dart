class SloAiConfig {
  /// Default/Fallback Gemini API Key.
  /// You can replace this key with your own Google AI Studio Gemini API Key.
  /// Note: The app will also look in Firestore (`app_config/global` or `app_config/ai`)
  /// for a remote `gemini_api_key` if available.
  static const String fallbackGeminiApiKey = "YOUR_GEMINI_API_KEY_HERE";

  /// The Gemini model used for generation (Standard stable model across all Google AI accounts)
  static const String geminiModel = "gemini-1.5-flash";

  /// 30-Second cooldown lock duration to prevent accidental double-tap or spam
  static const Duration generationCooldown = Duration(seconds: 30);
}
