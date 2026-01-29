import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String get geminiApiKey {
    return dotenv.env['GEMINI_API_KEY'] ?? ''; 
  }

  static String get openAiKey {
    return dotenv.env['OPEN_AI_KEY'] ?? '';
  }
}
