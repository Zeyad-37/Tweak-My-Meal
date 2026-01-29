import 'package:flutter/material.dart';
import '../../services/ai_service.dart';
import '../../services/openai_service.dart';
import '../widgets/glass_container.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final AiService _aiService = OpenAIService();
  bool _isLoading = false;
  String? _plan;

  Future<void> _generatePlan() async {
    setState(() => _isLoading = true);
    // In a real app we'd get preferences from UserProvider
    final plan = await _aiService.generateMealPlan(['Healthy', 'Low Carb']);
    setState(() {
      _plan = plan;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Planner'),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
         decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F172A), Color(0xFF000000)]),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GlassContainer(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _generatePlan,
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Generate Today\'s Plan'),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : _plan == null
                      ? const Center(child: Text('Tap to generate a plan based on your profile.'))
                      : SingleChildScrollView(
                          child: GlassContainer(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_plan!, style: const TextStyle(fontSize: 16)),
                                const Divider(height: 32),
                                ElevatedButton.icon(
                                  onPressed: () {}, 
                                  icon: const Icon(Icons.shopping_cart),
                                  label: const Text('Export Shopping List'),
                                )
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
