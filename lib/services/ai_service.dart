abstract class AiService {
  Future<String> analyzeMeal(String prompt, {String? imagePath});
  Future<String> suggestBetterVersion(String originalMeal);
  Future<String> generateMealPlan(List<String> preferences);
}

class MockAiService implements AiService {
  @override
  Future<String> analyzeMeal(String prompt, {String? imagePath}) async {
    await Future.delayed(const Duration(seconds: 2)); // Simulate network
    return "Based on '$prompt', this meal appears to be balanced but high in sodium. \n\n**Nutritional Estimate:**\n- Calories: 650\n- Protein: 35g\n- Carbs: 50g\n- Fat: 22g";
  }

  @override
  Future<String> suggestBetterVersion(String originalMeal) async {
    await Future.delayed(const Duration(seconds: 2));
    return "Here is a healthier version of $originalMeal:\n\n**Grilled Chicken with Quinoa**\n\n1. Replace fried chicken with grilled breast.\n2. Use Quinoa instead of white rice.\n3. Add steamed broccoli.";
  }

  @override
  Future<String> generateMealPlan(List<String> preferences) async {
    await Future.delayed(const Duration(seconds: 2));
    return "**Monday Meal Plan**\n\n- Breakfast: Oatmeal with berries\n- Lunch: Turkey Wrap\n- Dinner: Salmon with Asparagus";
  }
}
