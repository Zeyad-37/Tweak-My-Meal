import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';

import '../../core/config.dart';
import '../../providers/user_provider.dart';
import '../../services/openai_service.dart';
import '../../services/api_client.dart';
import '../../models/user_profile.dart';
import '../../models/chat_message.dart';
import '../widgets/glass_container.dart';

class OnboardingChatScreen extends StatefulWidget {
  const OnboardingChatScreen({super.key});

  @override
  State<OnboardingChatScreen> createState() => _OnboardingChatScreenState();
}

class _OnboardingChatScreenState extends State<OnboardingChatScreen> {
  final OpenAIService _openAiService = OpenAIService();
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  late OpenAIChatSession _chatSession;
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _startConversation();
  }

  Future<void> _startConversation() async {
    setState(() => _isTyping = true);
    try {
      _chatSession = _openAiService.startChat();
      final response = await _chatSession.sendMessage("START_INTERVIEW");
      _addMessage(response.isNotEmpty ? response : "Hello! I'm here to help.", false);
    } catch (e) {
      final keyStatus = Config.openAiKey.isEmpty ? "Key is Empty" : "Key starts with ${Config.openAiKey.substring(0, 7)}...";
      
      String helpText = "";
      if (e.toString().contains("401") || e.toString().contains("Unauthorized")) {
        helpText = "\n\nPOSSIBLE FIX:\n1. Check your OpenAI API Key in .env file.\n2. Ensure OPEN_AI_KEY is set correctly.\n3. Verify the key has not expired.";
      }
      
      _addMessage("Connection Error: $e\n\nDebug Info: $keyStatus$helpText", false);
    } finally {
      setState(() => _isTyping = false);
    }
  }

  void _sendMessage() async {
    if (_msgController.text.trim().isEmpty) return;
    
    final userText = _msgController.text;
    _msgController.clear();
    _addMessage(userText, true);

    setState(() => _isTyping = true);
    
    try {
      final botText = await _chatSession.sendMessage(userText);

      if (botText.contains("THANK_YOU_FINISHED") || _messages.length > 10) {
         _finishOnboarding();
      } else {
        _addMessage(botText, false);
      }
    } catch (e) {
      _addMessage("I'm having trouble hearing you ($e)", false);
    } finally {
      setState(() => _isTyping = false);
    }
  }

  Future<void> _finishOnboarding() async {
     _addMessage("Perfect! Creating your profile now...", false);
     setState(() => _isTyping = true);

     try {
       // Extract profile from conversation using the profiler
       final jsonStr = await _openAiService.extractProfile(_chatSession.history);
       final cleanJson = jsonStr.replaceAll('```json', '').replaceAll('```', '').trim();
       
       final Map<String, dynamic> data = jsonDecode(cleanJson);
       
       // Map the extracted data to our profile format
       final profileData = {
         'display_name': data['name'] ?? 'User',
         'cooking_skill': (data['cookingLevel'] ?? 'Beginner').toLowerCase(),
         'goals': [data['fitnessGoal'] ?? 'healthy eating'],
         'allergies': List<String>.from(data['allergies'] ?? []),
         'dislikes': List<String>.from(data['dietaryRestrictions'] ?? []),
         'likes': [],
         'equipment': [],
         'time_per_meal_minutes': 30,
       };
       
       // Save to backend
       final response = await _apiClient.createProfile(
         userId: 'user_0001',
         profile: profileData,
       );
       
       if (response.ok) {
         _addMessage("Profile saved! Let's start tweaking your meals.", false);
       }
       
       // Also save locally
       final profile = UserProfile(
         name: data['name'] ?? 'User',
         cookingLevel: data['cookingLevel'] ?? 'Beginner',
         fitnessGoal: data['fitnessGoal'] ?? 'Maintenance',
         dietaryRestrictions: List<String>.from(data['dietaryRestrictions'] ?? []),
         allergies: List<String>.from(data['allergies'] ?? []),
       );

       if (mounted) {
         context.read<UserProvider>().saveProfile(profile);
         // Navigate to the main chat screen
         await Future.delayed(const Duration(milliseconds: 500));
         context.go('/chat');
       }
     } catch (e) {
       _addMessage("Oops, I couldn't save that properly. Let's continue anyway! ($e)", false);
       if (mounted) {
         // Create default profile
         final defaultProfile = {
           'display_name': 'Friend',
           'cooking_skill': 'beginner',
           'goals': ['healthy eating'],
           'allergies': [],
           'dislikes': [],
           'likes': [],
           'equipment': [],
         };
         
         try {
           await _apiClient.createProfile(userId: 'user_0001', profile: defaultProfile);
         } catch (_) {}
         
         context.read<UserProvider>().saveProfile(UserProfile(name: 'Friend'));
         await Future.delayed(const Duration(milliseconds: 500));
         context.go('/chat');
       }
     }
  }

  void _addMessage(String text, bool isUser) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: isUser));
    });
    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Tweak My Meal'),
        backgroundColor: Colors.transparent,
        actions: [
          // Skip button for testing
          TextButton(
            onPressed: () async {
              final defaultProfile = {
                'display_name': 'Test User',
                'cooking_skill': 'intermediate',
                'goals': ['healthy eating'],
                'allergies': [],
                'dislikes': [],
                'likes': [],
                'equipment': ['stovetop', 'oven'],
                'time_per_meal_minutes': 30,
              };
              
              try {
                await _apiClient.createProfile(userId: 'user_0001', profile: defaultProfile);
              } catch (_) {}
              
              if (mounted) {
                context.go('/chat');
              }
            },
            child: const Text('Skip', style: TextStyle(color: Colors.white70)),
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
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Align(
                    alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 300),
                      decoration: BoxDecoration(
                        color: msg.isUser ? Theme.of(context).primaryColor : Colors.white10,
                        borderRadius: BorderRadius.circular(16).copyWith(
                          bottomRight: msg.isUser ? const Radius.circular(0) : null,
                          bottomLeft: !msg.isUser ? const Radius.circular(0) : null,
                        ),
                      ),
                      child: Text(msg.text, style: TextStyle(color: msg.isUser ? Colors.black : Colors.white)),
                    ),
                  );
                },
              ),
            ),
            if (_isTyping) 
              const Padding(
                padding: EdgeInsets.all(8.0), 
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text("Agent is typing...", style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            GlassContainer(
              borderRadius: 0,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Type your answer...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
