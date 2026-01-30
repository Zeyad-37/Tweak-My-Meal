import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// API Client for Tweak My Meal Backend
class ApiClient {
  static const String baseUrl = 'http://127.0.0.1:8080';
  
  // Singleton
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  // ============================================================================
  // User Profile
  // ============================================================================

  Future<ApiResponse> createProfile({
    required String userId,
    required Map<String, dynamic> profile,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/user/profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'profile': profile,
      }),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  Future<ApiResponse> getUserSummary({String userId = 'user_0001'}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/user/summary?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  // ============================================================================
  // Chat
  // ============================================================================

  /// Send a text-only chat turn
  Future<ApiResponse> chatTurnText({
    required String sessionId,
    required String text,
    String userId = 'user_0001',
    String modeHint = 'auto',
    int? maxTimeMinutes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/chat/turn'),
    );
    
    request.fields['user_id'] = userId;
    request.fields['session_id'] = sessionId;
    request.fields['text'] = text;
    request.fields['mode_hint'] = modeHint;
    
    if (maxTimeMinutes != null) {
      request.fields['client_context'] = jsonEncode({'max_time_minutes': maxTimeMinutes});
    }
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Send a chat turn with image(s)
  Future<ApiResponse> chatTurnWithImages({
    required String sessionId,
    required List<ImageData> images,
    String? text,
    String userId = 'user_0001',
    String modeHint = 'auto',
    int? maxTimeMinutes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/chat/turn'),
    );
    
    request.fields['user_id'] = userId;
    request.fields['session_id'] = sessionId;
    request.fields['mode_hint'] = modeHint;
    
    if (text != null && text.isNotEmpty) {
      request.fields['text'] = text;
    }
    
    if (maxTimeMinutes != null) {
      request.fields['client_context'] = jsonEncode({'max_time_minutes': maxTimeMinutes});
    }
    
    // Add images
    for (var i = 0; i < images.length; i++) {
      final img = images[i];
      request.files.add(http.MultipartFile.fromBytes(
        'images',
        img.bytes,
        filename: img.filename,
        contentType: MediaType('image', img.extension),
      ));
    }
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Select a suggestion to get the recipe
  Future<ApiResponse> selectSuggestion({
    required String sessionId,
    required String suggestionId,
    String userId = 'user_0001',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/chat/select'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'session_id': sessionId,
        'suggestion_id': suggestionId,
      }),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Get suggestion images (poll for async image generation)
  Future<ApiResponse> getSuggestionImages({
    required String sessionId,
    String userId = 'user_0001',
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/chat/images/$sessionId?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Modify the current analysis with additional ingredients/preferences
  Future<ApiResponse> modifyAnalysis({
    required String sessionId,
    required String modification,
    String userId = 'user_0001',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/chat/modify'),
    );
    
    request.fields['user_id'] = userId;
    request.fields['session_id'] = sessionId;
    request.fields['modification'] = modification;
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  // ============================================================================
  // Feedback
  // ============================================================================

  Future<ApiResponse> submitFeedback({
    required String mealId,
    required bool liked,
    bool cookedAgain = false,
    List<String> tags = const [],
    String? notes,
    String userId = 'user_0001',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/feedback'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'meal_id': mealId,
        'liked': liked,
        'cooked_again': cookedAgain,
        'tags': tags,
        'notes': notes,
      }),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  // ============================================================================
  // History
  // ============================================================================

  Future<ApiResponse> getHistory({
    String userId = 'user_0001',
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/history?user_id=$userId&limit=$limit&offset=$offset'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  // ============================================================================
  // Home Screen Data
  // ============================================================================

  /// Get all home screen data in one call
  Future<ApiResponse> getHomeData({String userId = 'user_0001'}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/home/home-data?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Get daily tip
  Future<ApiResponse> getDailyTip({String userId = 'user_0001'}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/home/daily-tip?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Get today's meals
  Future<ApiResponse> getTodaysMeals({String userId = 'user_0001'}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/home/todays-meals?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Save tweak selections as preferences
  Future<ApiResponse> saveTweakSelection({
    required String suggestionId,
    required List<String> selectedTweaks,
    String userId = 'user_0001',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/home/tweak-selection?user_id=$userId&suggestion_id=$suggestionId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'selected_tweaks': selectedTweaks,
      }),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Refresh suggested bites after profile/preference changes
  Future<ApiResponse> refreshSuggestedBites({String userId = 'user_0001'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/home/refresh-suggestions?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Get images for suggested bites (poll for async image generation)
  Future<ApiResponse> getBiteImages({String userId = 'user_0001'}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/home/bite-images?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  // ============================================================================
  // Conversation (Persistent Chat)
  // ============================================================================

  /// Get chat history
  Future<ApiResponse> getChatHistory({String userId = 'user_0001'}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/conversation/history?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Send a chat message
  Future<ApiResponse> sendChatMessage({
    required String message,
    String userId = 'user_0001',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/conversation/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'message': message,
      }),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Clear chat history
  Future<ApiResponse> clearChatHistory({String userId = 'user_0001'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/conversation/clear?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  // ============================================================================
  // Journal
  // ============================================================================

  /// Get weekly journal data (reflections + wisdom)
  Future<ApiResponse> getWeeklyJournal({String userId = 'user_0001'}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/journal/weekly?user_id=$userId'),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  /// Add a reflection
  Future<ApiResponse> addReflection({
    required String text,
    String userId = 'user_0001',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/journal/reflection'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'text': text,
      }),
    );
    return ApiResponse.fromJson(jsonDecode(response.body));
  }

  // ============================================================================
  // Health Check
  // ============================================================================

  Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

/// Image data for upload
class ImageData {
  final Uint8List bytes;
  final String filename;
  final String extension;

  ImageData({
    required this.bytes,
    required this.filename,
    this.extension = 'jpeg',
  });
}

/// API Response wrapper
class ApiResponse {
  final bool ok;
  final dynamic data;
  final ApiError? error;

  ApiResponse({required this.ok, this.data, this.error});

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      ok: json['ok'] ?? false,
      data: json['data'],
      error: json['error'] != null ? ApiError.fromJson(json['error']) : null,
    );
  }

  String get errorMessage => error?.message ?? 'Unknown error';
}

class ApiError {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  ApiError({required this.code, required this.message, this.details});

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      code: json['code'] ?? 'UNKNOWN',
      message: json['message'] ?? 'Unknown error',
      details: json['details'],
    );
  }
}
