import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import 'ai_service.dart';
import 'agent_prompts.dart';

/// Chat message for maintaining conversation history
class OpenAIChatMessage {
  final String role; // 'system', 'user', or 'assistant'
  final String content;

  OpenAIChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// A chat session that maintains conversation history
class OpenAIChatSession {
  final List<OpenAIChatMessage> _history = [];
  final OpenAIService _service;
  final String _model;

  OpenAIChatSession(this._service, this._model, {String? systemPrompt}) {
    if (systemPrompt != null) {
      _history.add(OpenAIChatMessage(role: 'system', content: systemPrompt));
    }
  }

  List<OpenAIChatMessage> get history => List.unmodifiable(_history);

  Future<String> sendMessage(String message) async {
    _history.add(OpenAIChatMessage(role: 'user', content: message));

    final response = await _service._chatCompletion(_history, _model);
    _history.add(OpenAIChatMessage(role: 'assistant', content: response));

    return response;
  }
}

class OpenAIService implements AiService {
  static const String _baseUrl = 'https://api.openai.com/v1';
  static const String _defaultModel = 'gpt-4o';
  static const String _visionModel = 'gpt-4o'; // GPT-4o supports vision

  String get _apiKey => Config.openAiKey;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      };

  // --- Internal API Methods ---

  Future<String> _chatCompletion(
    List<OpenAIChatMessage> messages,
    String model,
  ) async {
    final url = Uri.parse('$_baseUrl/chat/completions');

    final body = jsonEncode({
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': 0.7,
      'max_tokens': 2048,
    });

    final response = await http.post(url, headers: _headers, body: body);

    if (response.statusCode != 200) {
      throw Exception(
          'OpenAI API error: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  Future<String> _singlePrompt(String systemPrompt, String userPrompt) async {
    final messages = [
      OpenAIChatMessage(role: 'system', content: systemPrompt),
      OpenAIChatMessage(role: 'user', content: userPrompt),
    ];
    return _chatCompletion(messages, _defaultModel);
  }

  // --- Conversational Onboarding ---

  OpenAIChatSession startChat() {
    return OpenAIChatSession(
      this,
      _defaultModel,
      systemPrompt: AgentPrompts.interviewerInit,
    );
  }

  Future<String> extractProfile(List<OpenAIChatMessage> history) async {
    // Build conversation log from history
    final conversationLog = history
        .where((m) => m.role != 'system')
        .map((m) => '${m.role}: ${m.content}')
        .join('\n');

    return _singlePrompt(
      AgentPrompts.profiler,
      'Here is the conversation:\n$conversationLog',
    );
  }

  // --- Core Features (AiService Implementation) ---

  @override
  Future<String> analyzeMeal(String prompt, {String? imagePath}) async {
    // For text-only analysis
    if (imagePath == null) {
      return _singlePrompt(
        AgentPrompts.critic,
        'Analyze this meal: $prompt',
      );
    }

    // TODO: Implement image analysis with base64 encoding for vision
    return "Image analysis not fully implemented in web prototype yet.";
  }

  @override
  Future<String> suggestBetterVersion(String originalMeal) async {
    return _singlePrompt(
      AgentPrompts.chef,
      'Tweak this meal: $originalMeal',
    );
  }

  @override
  Future<String> generateMealPlan(List<String> preferences) async {
    String level = preferences.isNotEmpty ? preferences[0] : 'Beginner';
    String goal = preferences.length > 1 ? preferences[1] : 'Healthy';
    String restrictions = preferences.length > 2 ? preferences[2] : 'None';

    final prompt = AgentPrompts.planner
        .replaceAll('{level}', level)
        .replaceAll('{goal}', goal)
        .replaceAll('{restrictions}', restrictions);

    final messages = [
      OpenAIChatMessage(role: 'user', content: prompt),
    ];
    return _chatCompletion(messages, _defaultModel);
  }
}
