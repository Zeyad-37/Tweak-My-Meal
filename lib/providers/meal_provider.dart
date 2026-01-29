import 'package:flutter/material.dart';
import '../services/openai_service.dart';
import '../services/ai_service.dart';
import '../models/meal_entry.dart';

class MealProvider extends ChangeNotifier {
  final AiService _aiService = OpenAIService();
  final List<MealEntry> _history = [];
  
  bool _isLoading = false;
  String? _lastResult;

  List<MealEntry> get history => List.unmodifiable(_history);
  bool get isLoading => _isLoading;
  String? get lastResult => _lastResult;

  Future<void> analyzeMeal(String prompt) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _aiService.analyzeMeal(prompt);
      _lastResult = response;
      _history.add(MealEntry(
        id: DateTime.now().toString(),
        timestamp: DateTime.now(),
        inputType: 'text',
        inputContent: prompt,
        aiResponse: response,
      ));
    } catch (e) {
      _lastResult = "Error analyzing meal: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
