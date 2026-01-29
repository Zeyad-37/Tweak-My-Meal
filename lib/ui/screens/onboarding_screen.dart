import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/user_provider.dart';
import '../../models/user_profile.dart';
import '../widgets/glass_container.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  String _cookingLevel = 'Beginner';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF111827)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Welcome to\nTweak My Meal',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 48),
                GlassContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What should we call you?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Enter your name',
                          prefixIcon: Icon(Icons.person, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Cooking Experience?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _buildLevelSelector(),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _completeOnboarding,
                          child: const Text('Start My Journey'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'Beginner', label: Text('Beginner')),
        ButtonSegment(value: 'Intermediate', label: Text('Medium')),
        ButtonSegment(value: 'Advanced', label: Text('Pro')),
      ],
      selected: {_cookingLevel},
      onSelectionChanged: (Set<String> newSelection) {
        setState(() {
          _cookingLevel = newSelection.first;
        });
      },
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.selected)) {
            return Theme.of(context).primaryColor;
          }
          return Colors.white10;
        }),
        foregroundColor: MaterialStateProperty.resolveWith<Color>((states) {
           if (states.contains(MaterialState.selected)) {
            return Colors.black;
          }
          return Colors.white;
        }),
      ),
    );
  }

  void _completeOnboarding() {
    if (_nameController.text.isEmpty) return;
    
    final profile = UserProfile(
      name: _nameController.text,
      cookingLevel: _cookingLevel,
    );
    
    context.read<UserProvider>().saveProfile(profile);
    context.go('/dashboard');
  }
}
