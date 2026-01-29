import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';

import '../../services/api_client.dart';
import '../widgets/glass_container.dart';

/// Main chat screen for meal analysis flow
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  
  late String _sessionId;
  final List<ChatItem> _items = [];
  bool _isLoading = false;
  List<Uint8List>? _pendingImages;
  
  // Current state
  String? _currentMealId;
  List<SuggestionItem>? _pendingSuggestions;

  @override
  void initState() {
    super.initState();
    _sessionId = const Uuid().v4();
    _addSystemMessage("Hi! I'm your nutrition assistant. Tell me what you ate or upload a photo, and I'll suggest healthier alternatives!");
  }

  void _addSystemMessage(String text) {
    setState(() {
      _items.add(ChatItem(text: text, type: ChatItemType.assistant));
    });
    _scrollToBottom();
  }

  void _addUserMessage(String text, {List<Uint8List>? images}) {
    setState(() {
      _items.add(ChatItem(
        text: text,
        type: ChatItemType.user,
        images: images,
      ));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
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

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pendingImages ??= [];
        _pendingImages!.add(bytes);
      });
    }
  }

  Future<void> _takePhoto() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pendingImages ??= [];
        _pendingImages!.add(bytes);
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty && (_pendingImages == null || _pendingImages!.isEmpty)) {
      return;
    }
    
    _msgController.clear();
    final images = _pendingImages;
    setState(() {
      _pendingImages = null;
    });
    
    _addUserMessage(text.isNotEmpty ? text : "📷 Photo uploaded", images: images);
    
    setState(() => _isLoading = true);
    
    try {
      ApiResponse response;
      
      if (images != null && images.isNotEmpty) {
        // Send with images
        response = await _api.chatTurnWithImages(
          sessionId: _sessionId,
          images: images.asMap().entries.map((e) => ImageData(
            bytes: e.value,
            filename: 'image_${e.key}.jpg',
          )).toList(),
          text: text.isNotEmpty ? text : null,
        );
      } else {
        // Text only
        response = await _api.chatTurnText(
          sessionId: _sessionId,
          text: text,
        );
      }
      
      if (response.ok) {
        _handleResponse(response.data);
      } else {
        _addSystemMessage("Sorry, something went wrong: ${response.errorMessage}");
      }
    } catch (e) {
      _addSystemMessage("Connection error: $e\n\nMake sure the backend is running on http://127.0.0.1:8080");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleResponse(Map<String, dynamic> data) {
    final kind = data['kind'] as String?;
    
    switch (kind) {
      case 'follow_up':
        _handleFollowUp(data);
        break;
      case 'suggestions':
        _handleSuggestions(data);
        break;
      case 'recipe':
        _handleRecipe(data);
        break;
      default:
        _addSystemMessage("Received unknown response type: $kind");
    }
  }

  void _handleFollowUp(Map<String, dynamic> data) {
    final questions = List<String>.from(data['questions'] ?? []);
    if (questions.isNotEmpty) {
      _addSystemMessage(questions.join('\n\n'));
    }
  }

  void _handleSuggestions(Map<String, dynamic> data) {
    final suggestions = (data['suggestions'] as List?)
        ?.map((s) => SuggestionItem.fromJson(s))
        .toList() ?? [];
    
    setState(() {
      _pendingSuggestions = suggestions;
    });
    
    // Build message with suggestions
    final sb = StringBuffer("Here are some healthier options:\n\n");
    for (var i = 0; i < suggestions.length; i++) {
      final s = suggestions[i];
      sb.writeln("${i + 1}. **${s.title}**");
      sb.writeln("   ${s.summary}");
      sb.writeln("   ⏱️ ${s.estimatedTime} min | ${s.difficulty}");
      sb.writeln();
    }
    sb.writeln("Tap a suggestion below to get the full recipe!");
    
    setState(() {
      _items.add(ChatItem(
        text: sb.toString(),
        type: ChatItemType.assistant,
        suggestions: suggestions,
      ));
    });
    _scrollToBottom();
  }

  void _handleRecipe(Map<String, dynamic> data) {
    final mealId = data['meal_id'] as String?;
    final recipe = data['recipe'] as Map<String, dynamic>?;
    
    setState(() {
      _currentMealId = mealId;
      _pendingSuggestions = null;
    });
    
    if (recipe != null) {
      _items.add(ChatItem(
        text: '',
        type: ChatItemType.recipe,
        recipe: RecipeItem.fromJson(recipe),
        mealId: mealId,
      ));
      _scrollToBottom();
    }
  }

  Future<void> _selectSuggestion(SuggestionItem suggestion) async {
    setState(() => _isLoading = true);
    
    _addUserMessage("I'd like: ${suggestion.title}");
    
    try {
      final response = await _api.selectSuggestion(
        sessionId: _sessionId,
        suggestionId: suggestion.id,
      );
      
      if (response.ok) {
        _handleResponse(response.data);
      } else {
        _addSystemMessage("Error: ${response.errorMessage}");
      }
    } catch (e) {
      _addSystemMessage("Connection error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitFeedback(bool liked) async {
    if (_currentMealId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final response = await _api.submitFeedback(
        mealId: _currentMealId!,
        liked: liked,
      );
      
      if (response.ok) {
        _addSystemMessage(liked 
            ? "Great! I've noted that you liked this meal. I'll remember your preferences!"
            : "Thanks for the feedback! I'll try to suggest something better next time.");
        
        // Start new session for next interaction
        setState(() {
          _currentMealId = null;
          _sessionId = const Uuid().v4();
        });
      }
    } catch (e) {
      _addSystemMessage("Couldn't save feedback: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tweak My Meal'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _items.clear();
                _sessionId = const Uuid().v4();
                _currentMealId = null;
                _pendingSuggestions = null;
              });
              _addSystemMessage("New session started! What would you like to eat today?");
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF000000)],
          ),
        ),
        child: Column(
          children: [
            // Chat list
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (context, index) => _buildChatItem(_items[index]),
              ),
            ),
            
            // Loading indicator
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text("Thinking...", style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            
            // Pending images preview
            if (_pendingImages != null && _pendingImages!.isNotEmpty)
              Container(
                height: 80,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingImages!.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _pendingImages![index],
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _pendingImages!.removeAt(index);
                                if (_pendingImages!.isEmpty) {
                                  _pendingImages = null;
                                }
                              });
                            },
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            
            // Input area
            GlassContainer(
              borderRadius: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white70),
                    onPressed: _pickImage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.white70),
                    onPressed: _takePhoto,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Describe your meal...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(ChatItem item) {
    switch (item.type) {
      case ChatItemType.user:
        return _buildUserMessage(item);
      case ChatItemType.assistant:
        return _buildAssistantMessage(item);
      case ChatItemType.recipe:
        return _buildRecipeCard(item);
    }
  }

  Widget _buildUserMessage(ChatItem item) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 50),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: const Radius.circular(0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (item.images != null)
              Wrap(
                spacing: 4,
                children: item.images!.map((img) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(img, width: 100, height: 100, fit: BoxFit.cover),
                )).toList(),
              ),
            if (item.text.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: item.images != null ? 8 : 0),
                child: Text(item.text, style: const TextStyle(color: Colors.black)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(ChatItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8, right: 50),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomLeft: const Radius.circular(0),
              ),
            ),
            child: Text(
              item.text,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        // Suggestion buttons
        if (item.suggestions != null && item.suggestions!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.suggestions!.map((s) => ElevatedButton(
                onPressed: _isLoading ? null : () => _selectSuggestion(s),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                ),
                child: Text(s.title),
              )).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildRecipeCard(ChatItem item) {
    final recipe = item.recipe!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recipe.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              recipe.summary,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildChip('⏱️ ${recipe.timeMinutes} min'),
                const SizedBox(width: 8),
                _buildChip('👨‍🍳 ${recipe.difficulty}'),
                const SizedBox(width: 8),
                _buildChip('🍽️ ${recipe.servings} servings'),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            const Text(
              'Ingredients',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            ...recipe.ingredients.map((i) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text('• ${i.quantity} ${i.name}', style: const TextStyle(color: Colors.white70)),
            )),
            const SizedBox(height: 12),
            const Text(
              'Instructions',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            ...recipe.steps.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${e.key + 1}. ${e.value}', style: const TextStyle(color: Colors.white70)),
            )),
            if (recipe.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(recipe.warnings.join(', '), style: const TextStyle(color: Colors.orange))),
                  ],
                ),
              ),
            ],
            const Divider(color: Colors.white24, height: 24),
            const Text('Did you like this recipe?', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _submitFeedback(true),
                  icon: const Icon(Icons.thumb_up),
                  label: const Text('Love it!'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _submitFeedback(false),
                  icon: const Icon(Icons.thumb_down),
                  label: const Text('Not for me'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70)),
    );
  }
}

// ============================================================================
// Data Models
// ============================================================================

enum ChatItemType { user, assistant, recipe }

class ChatItem {
  final String text;
  final ChatItemType type;
  final List<Uint8List>? images;
  final List<SuggestionItem>? suggestions;
  final RecipeItem? recipe;
  final String? mealId;

  ChatItem({
    required this.text,
    required this.type,
    this.images,
    this.suggestions,
    this.recipe,
    this.mealId,
  });
}

class SuggestionItem {
  final String id;
  final String title;
  final String summary;
  final List<String> healthRationale;
  final List<String> tags;
  final int estimatedTime;
  final String difficulty;

  SuggestionItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.healthRationale,
    required this.tags,
    required this.estimatedTime,
    required this.difficulty,
  });

  factory SuggestionItem.fromJson(Map<String, dynamic> json) {
    return SuggestionItem(
      id: json['suggestion_id'] ?? '',
      title: json['title'] ?? '',
      summary: json['summary'] ?? '',
      healthRationale: List<String>.from(json['health_rationale'] ?? []),
      tags: List<String>.from(json['tags'] ?? []),
      estimatedTime: json['estimated_time_minutes'] ?? 30,
      difficulty: json['difficulty'] ?? 'medium',
    );
  }
}

class RecipeItem {
  final String name;
  final String summary;
  final List<String> healthRationale;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final int timeMinutes;
  final String difficulty;
  final List<String> equipment;
  final int servings;
  final List<String> warnings;

  RecipeItem({
    required this.name,
    required this.summary,
    required this.healthRationale,
    required this.ingredients,
    required this.steps,
    required this.timeMinutes,
    required this.difficulty,
    required this.equipment,
    required this.servings,
    required this.warnings,
  });

  factory RecipeItem.fromJson(Map<String, dynamic> json) {
    return RecipeItem(
      name: json['name'] ?? '',
      summary: json['summary'] ?? '',
      healthRationale: List<String>.from(json['health_rationale'] ?? []),
      ingredients: (json['ingredients'] as List?)
          ?.map((i) => RecipeIngredient.fromJson(i))
          .toList() ?? [],
      steps: List<String>.from(json['steps'] ?? []),
      timeMinutes: json['time_minutes'] ?? 30,
      difficulty: json['difficulty'] ?? 'medium',
      equipment: List<String>.from(json['equipment'] ?? []),
      servings: json['servings'] ?? 1,
      warnings: List<String>.from(json['warnings'] ?? []),
    );
  }
}

class RecipeIngredient {
  final String name;
  final String quantity;
  final bool optional;
  final List<String> substitutes;

  RecipeIngredient({
    required this.name,
    required this.quantity,
    required this.optional,
    required this.substitutes,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name'] ?? '',
      quantity: json['quantity'] ?? '',
      optional: json['optional'] ?? false,
      substitutes: List<String>.from(json['substitutes'] ?? []),
    );
  }
}
