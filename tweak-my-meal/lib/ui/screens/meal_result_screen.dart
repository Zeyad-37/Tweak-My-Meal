import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';

import '../../services/api_client.dart';
import '../widgets/glass_container.dart';

class MealResultScreen extends StatefulWidget {
  final Uint8List? imageBytes;
  final String? mealText;
  final VoidCallback? onComplete;

  const MealResultScreen({
    super.key,
    this.imageBytes,
    this.mealText,
    this.onComplete,
  });

  @override
  State<MealResultScreen> createState() => _MealResultScreenState();
}

class _MealResultScreenState extends State<MealResultScreen> {
  final ApiClient _api = ApiClient();
  final String _sessionId = const Uuid().v4();
  final TextEditingController _modifyController = TextEditingController();

  bool _isLoading = true;
  String _status = 'Analyzing your meal...';
  
  // Analysis results
  String? _inputKind;
  Map<String, dynamic>? _visionResult;
  List<Map<String, dynamic>> _suggestions = [];
  Map<String, dynamic>? _selectedRecipe;
  String? _mealId;
  String? _recipeImageUrl;
  
  // Track modifications
  List<String> _modifications = [];
  
  // Image loading state
  Map<String, String> _suggestionImages = {};
  bool _imagesLoading = true;
  
  String? _error;

  @override
  void initState() {
    super.initState();
    _analyzeMeal();
  }

  @override
  void dispose() {
    _modifyController.dispose();
    super.dispose();
  }

  Future<void> _analyzeMeal() async {
    setState(() {
      _isLoading = true;
      _status = widget.imageBytes != null ? 'Analyzing your photo...' : 'Understanding your meal...';
    });

    try {
      ApiResponse response;

      if (widget.imageBytes != null) {
        // Image analysis
        response = await _api.chatTurnWithImages(
          sessionId: _sessionId,
          images: [
            ImageData(
              bytes: widget.imageBytes!,
              filename: 'meal.jpg',
            ),
          ],
          text: widget.mealText,
        );
      } else if (widget.mealText != null) {
        // Text analysis
        response = await _api.chatTurnText(
          sessionId: _sessionId,
          text: widget.mealText!,
        );
      } else {
        setState(() {
          _error = 'No meal data provided';
          _isLoading = false;
        });
        return;
      }

      if (response.ok && response.data != null) {
        final kind = response.data['kind'] as String?;

        if (kind == 'suggestions') {
          final suggestions = List<Map<String, dynamic>>.from(
            response.data['suggestions'] ?? [],
          );
          setState(() {
            _inputKind = response.data['source']?['input_kind'];
            _visionResult = response.data['source']?['vision_result'];
            _suggestions = suggestions;
            _status = _getStatusMessage();
            _isLoading = false;
            _imagesLoading = true;
          });
          
          // Start polling for images in background
          _pollForImages();
        } else if (kind == 'follow_up') {
          // Need more info
          final questions = List<String>.from(response.data['questions'] ?? []);
          setState(() {
            _error = questions.isNotEmpty ? questions.first : 'Need more information';
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = 'Unexpected response type';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = response.errorMessage;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
        _isLoading = false;
      });
    }
  }

  String _getStatusMessage() {
    if (_inputKind == 'meal_photo' || _inputKind == 'text_meal') {
      return 'Here are healthier alternatives:';
    } else if (_inputKind == 'ingredients_photo' || _inputKind == 'text_ingredients') {
      return 'Here\'s what you can make:';
    }
    return 'Suggestions for you:';
  }

  Future<void> _pollForImages() async {
    // Poll every 2 seconds until all images are ready
    int attempts = 0;
    const maxAttempts = 30; // Max 60 seconds
    
    while (mounted && _imagesLoading && attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 2));
      attempts++;
      
      try {
        final response = await _api.getSuggestionImages(sessionId: _sessionId);
        
        if (response.ok && response.data != null) {
          final images = Map<String, String>.from(response.data['images'] ?? {});
          final allReady = response.data['all_ready'] ?? false;
          
          if (images.isNotEmpty) {
            setState(() {
              _suggestionImages = images;
              // Update suggestions with image URLs
              for (var s in _suggestions) {
                final id = s['suggestion_id'] as String?;
                if (id != null && images.containsKey(id)) {
                  s['image_url'] = images[id];
                }
              }
            });
          }
          
          if (allReady) {
            setState(() => _imagesLoading = false);
            break;
          }
        }
      } catch (e) {
        print('Error polling for images: $e');
      }
    }
    
    if (mounted) {
      setState(() => _imagesLoading = false);
    }
  }

  Future<void> _addModificationAndRegenerate() async {
    final text = _modifyController.text.trim();
    if (text.isEmpty) return;

    _modifyController.clear();
    
    setState(() {
      _modifications.add(text);
      _isLoading = true;
      _status = 'Updating suggestions with "$text"...';
      _selectedRecipe = null;
      _recipeImageUrl = null;
    });

    try {
      // Use the dedicated modify endpoint
      final response = await _api.modifyAnalysis(
        sessionId: _sessionId,
        modification: text,
      );

      if (response.ok && response.data != null) {
        final kind = response.data['kind'] as String?;

        if (kind == 'suggestions') {
          setState(() {
            _suggestions = List<Map<String, dynamic>>.from(
              response.data['suggestions'] ?? [],
            );
            _suggestionImages = {};
            _imagesLoading = true;
            _status = _getStatusMessage();
            _isLoading = false;
          });
          // Start polling for new images
          _pollForImages();
        } else {
          setState(() {
            _status = 'Suggestions updated';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = response.errorMessage;
          _isLoading = false;
        });
      }

      // Save the preference to user profile via conversation API
      _savePreferenceInBackground(text);
      
    } catch (e) {
      setState(() {
        _error = 'Error updating suggestions: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _savePreferenceInBackground(String modification) async {
    // Save the modification as a preference via the chat API
    // This learns that user likes/has these ingredients
    try {
      await _api.sendChatMessage(
        message: 'Remember: I have $modification available and like to use it in my cooking.',
      );
    } catch (e) {
      // Silent fail - preference saving is non-critical
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    setState(() {
      _isLoading = true;
      _status = 'Generating recipe...';
    });

    try {
      final response = await _api.selectSuggestion(
        sessionId: _sessionId,
        suggestionId: suggestion['suggestion_id'],
      );

      if (response.ok && response.data != null) {
        setState(() {
          _selectedRecipe = response.data['recipe'];
          _mealId = response.data['meal_id'];
          _recipeImageUrl = response.data['image_url'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response.errorMessage;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error generating recipe: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _logMeal() async {
    if (_mealId == null) return;

    try {
      // The meal is already logged when selected, just show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meal logged! Check your Journal.'),
            backgroundColor: Colors.green,
          ),
        );

        // Return to home
        widget.onComplete?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to log meal'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submitFeedback(bool liked) async {
    if (_mealId == null) return;

    try {
      await _api.submitFeedback(
        mealId: _mealId!,
        liked: liked,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(liked 
                ? 'Great! Saved to your favorites.' 
                : 'Thanks for the feedback!'),
            backgroundColor: liked ? Colors.green : Colors.grey,
          ),
        );

        // Return to home
        widget.onComplete?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Ignore feedback errors
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            widget.onComplete?.call();
            Navigator.of(context).pop();
          },
        ),
        title: Text(_selectedRecipe != null ? 'Recipe' : 'Meal Analysis'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _status,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.orange, size: 64),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedRecipe != null) {
      return _buildRecipeView();
    }

    return _buildSuggestionsView();
  }

  Widget _buildSuggestionsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image preview
          if (widget.imageBytes != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: MemoryImage(widget.imageBytes!),
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // Detection info
          if (_visionResult != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _inputKind?.contains('meal') == true 
                        ? Icons.restaurant 
                        : Icons.shopping_basket,
                    color: Colors.purple[300],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _visionResult!['detected']?['meal_name'] ?? 
                          (_inputKind?.contains('ingredients') == true ? 'Ingredients detected' : 'Meal detected'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_visionResult!['detected']?['cuisine_hint'] != null)
                          Text(
                            _visionResult!['detected']['cuisine_hint'],
                            style: TextStyle(color: Colors.grey[400], fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Status
          Text(
            _status,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Modification input
          _buildModificationInput(),
          const SizedBox(height: 16),

          // Show current modifications
          if (_modifications.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _modifications.map((m) => _buildModificationChip(m)).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Suggestions
          ..._suggestions.map((s) => _buildSuggestionCard(s)),
        ],
      ),
    );
  }

  Widget _buildModificationInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.add_circle_outline, color: Colors.purple[300], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _modifyController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Add eggs, spinach, or any ingredient...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _addModificationAndRegenerate(),
            ),
          ),
          TextButton(
            onPressed: _addModificationAndRegenerate,
            child: Text(
              'Update',
              style: TextStyle(color: Colors.purple[300], fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModificationChip(String modification) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, color: Colors.purple, size: 14),
          const SizedBox(width: 6),
          Text(
            modification,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(Map<String, dynamic> suggestion) {
    final imageUrl = suggestion['image_url'] as String?;
    
    return GestureDetector(
      onTap: () => _selectSuggestion(suggestion),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: imageUrl != null
                  ? Image.network(
                      imageUrl,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 160,
                          color: Colors.grey[900],
                          child: const Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 160,
                          color: Colors.grey[900],
                          child: Center(child: Icon(Icons.restaurant, color: Colors.grey[700], size: 48)),
                        );
                      },
                    )
                  : Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Center(
                        child: _imagesLoading
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.purple[300],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Generating image...',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  ),
                                ],
                              )
                            : Icon(Icons.restaurant, color: Colors.grey[700], size: 48),
                      ),
                    ),
            ),
            
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          suggestion['title'] ?? 'Suggestion',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, color: Colors.purple[300], size: 18),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    suggestion['summary'] ?? '',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildChip('${suggestion['estimated_time_minutes'] ?? 30} min'),
                      const SizedBox(width: 8),
                      _buildChip(suggestion['difficulty'] ?? 'medium'),
                    ],
                  ),
                  if (suggestion['health_rationale'] != null && 
                      (suggestion['health_rationale'] as List).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...((suggestion['health_rationale'] as List).take(2).map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.toString(),
                              style: TextStyle(color: Colors.grey[400], fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeView() {
    final recipe = _selectedRecipe!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recipe image
          if (_recipeImageUrl != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _recipeImageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.purple.shade900,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                          color: Colors.white54,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.purple.shade900,
                    child: Icon(Icons.restaurant, color: Colors.white.withValues(alpha: 0.5), size: 60),
                  ),
                ),
              ),
            ),
          
          // Recipe header
          Text(
            recipe['name'] ?? 'Recipe',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            recipe['summary'] ?? '',
            style: TextStyle(color: Colors.grey[400], fontSize: 15),
          ),
          const SizedBox(height: 16),
          
          // Stats
          Row(
            children: [
              _buildChip('⏱️ ${recipe['time_minutes'] ?? 30} min'),
              const SizedBox(width: 8),
              _buildChip('👨‍🍳 ${recipe['difficulty'] ?? 'medium'}'),
              const SizedBox(width: 8),
              _buildChip('🍽️ ${recipe['servings'] ?? 2} servings'),
            ],
          ),
          const SizedBox(height: 24),

          // Health rationale
          if (recipe['health_rationale'] != null && 
              (recipe['health_rationale'] as List).isNotEmpty) ...[
            _buildSection('Why it\'s healthier', 
              (recipe['health_rationale'] as List).map((r) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.toString(), style: const TextStyle(color: Colors.white70))),
                ],
              )).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Ingredients
          _buildSection('Ingredients',
            (recipe['ingredients'] as List? ?? []).map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.purple[300], fontSize: 16)),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${i['quantity']} ',
                            style: TextStyle(color: Colors.grey[400], fontSize: 15),
                          ),
                          TextSpan(
                            text: i['name'],
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                          if (i['optional'] == true)
                            TextSpan(
                              text: ' (optional)',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
          const SizedBox(height: 24),

          // Steps
          _buildSection('Instructions',
            (recipe['steps'] as List? ?? []).asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        '${e.key + 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      e.value.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
          const SizedBox(height: 24),

          // Warnings
          if (recipe['warnings'] != null && (recipe['warnings'] as List).isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (recipe['warnings'] as List).join(', '),
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // Go back to suggestions with modifications
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _selectedRecipe = null;
                _recipeImageUrl = null;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to suggestions'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
          const SizedBox(height: 24),

          // Log Meal button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _logMeal,
              icon: const Icon(Icons.add_circle_outline, size: 22),
              label: const Text('Log This Meal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Feedback
          const Text(
            'Did you like this recipe?',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _submitFeedback(true),
                  icon: const Icon(Icons.thumb_up),
                  label: const Text('Love it!'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _submitFeedback(false),
                  icon: const Icon(Icons.thumb_down),
                  label: const Text('Not for me'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
