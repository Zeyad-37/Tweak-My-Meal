import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/meal_provider.dart';
import '../widgets/glass_container.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _promptController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Tweak My Meal'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => GoRouter.of(context).push('/planner'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F172A), Color(0xFF000000)]),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAnalysisCard(),
                const SizedBox(height: 24),
                Text(
                  'Recent Meals',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Expanded(child: _buildHistoryList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisCard() {
    return GlassContainer(
      child: Column(
        children: [
          TextField(
            controller: _promptController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Type what you ate or upload a photo...',
              border: InputBorder.none,
              filled: false,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {}, // TODO: Image Picker
                icon: const Icon(Icons.camera_alt, color: Colors.white70),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (_promptController.text.isNotEmpty) {
                    context.read<MealProvider>().analyzeMeal(_promptController.text);
                    _promptController.clear();
                  }
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Analyze'),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return Consumer<MealProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (provider.history.isEmpty) {
          return const Center(child: Text('No meals tracked yet.'));
        }

        return ListView.builder(
          itemCount: provider.history.length,
          itemBuilder: (context, index) {
            final meal = provider.history[provider.history.length - 1 - index]; // Reverse order
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: GlassContainer(
                opacity: 0.05,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.inputContent,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Divider(color: Colors.white24),
                    Text(
                      meal.aiResponse,
                      style: const TextStyle(color: Colors.white70),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
