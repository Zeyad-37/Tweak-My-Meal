import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

import '../../services/api_client.dart';
import 'chat_drawer.dart';
import 'meal_result_screen.dart';
import 'journal_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeContent(onProfileUpdated: () => setState(() {})),
          const JournalScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, 'Home'),
                _buildNavItem(1, Icons.auto_stories_rounded, 'Journal'),
                _buildNavItem(2, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.purple[300] : Colors.grey[600],
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.purple[300] : Colors.grey[600],
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeContent extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const HomeContent({super.key, this.onProfileUpdated});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final ApiClient _api = ApiClient();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  String? _displayName;
  String _dailyTip = "Eating slowly helps digestion and lets you enjoy each bite more.";
  List<Map<String, dynamic>> _todaysMeals = [];
  List<Map<String, dynamic>> _suggestedBites = [];
  Map<String, Set<String>> _selectedTweaks = {}; // suggestionId -> selected tweaks
  bool _isPollingImages = false;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    setState(() => _isLoading = true);

    try {
      final response = await _api.getHomeData();

      if (response.ok && response.data != null) {
        setState(() {
          _displayName = response.data['user']?['display_name'];
          _dailyTip = response.data['daily_tip'] ??
              "Eating slowly helps digestion and lets you enjoy each bite more.";
          _todaysMeals =
              List<Map<String, dynamic>>.from(response.data['todays_meals'] ?? []);
          _suggestedBites =
              List<Map<String, dynamic>>.from(response.data['suggested_bites'] ?? []);
        });
        
        // Start polling for images if any bite is missing an image
        final needsImages = _suggestedBites.any((b) => b['image_url'] == null);
        if (needsImages && !_isPollingImages) {
          _pollForBiteImages();
        }
      }
    } catch (e) {
      // Use fallback data
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pollForBiteImages() async {
    if (_isPollingImages) return;
    _isPollingImages = true;
    
    // Poll for up to 60 seconds
    for (int i = 0; i < 12; i++) {
      await Future.delayed(const Duration(seconds: 5));
      
      if (!mounted) break;
      
      try {
        final response = await _api.getBiteImages();
        if (response.ok && response.data != null) {
          final images = Map<String, dynamic>.from(response.data['images'] ?? {});
          final stillGenerating = response.data['generating'] ?? false;
          
          // Update suggested bites with images
          bool anyUpdated = false;
          for (var bite in _suggestedBites) {
            final sid = bite['suggestion_id'] as String?;
            if (sid != null && images.containsKey(sid) && bite['image_url'] == null) {
              bite['image_url'] = images[sid];
              anyUpdated = true;
            }
          }
          
          if (anyUpdated && mounted) {
            setState(() {});
          }
          
          // Stop polling if no longer generating
          if (!stillGenerating) break;
        }
      } catch (e) {
        // Ignore polling errors
      }
    }
    
    _isPollingImages = false;
  }

  void _openChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatDrawer(
        onProfileUpdated: () {
          // Refresh suggestions when profile changes in chat
          _refreshSuggestions();
          widget.onProfileUpdated?.call();
        },
      ),
    );
  }

  Future<void> _refreshSuggestions() async {
    try {
      // Force refresh suggested bites based on updated profile
      await _api.refreshSuggestedBites();
      // Reload all home data
      await _loadHomeData();
    } catch (e) {
      // Ignore refresh errors, data will update on next load
    }
  }

  Future<void> _openCamera() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      _navigateToMealResult(imageBytes: bytes);
    }
  }

  Future<void> _openGallery() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      _navigateToMealResult(imageBytes: bytes);
    }
  }

  void _navigateToMealResult({Uint8List? imageBytes, String? mealText}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MealResultScreen(
          imageBytes: imageBytes,
          mealText: mealText,
          onComplete: () {
            _loadHomeData();
          },
        ),
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.white),
                title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _openCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title:
                    const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _openGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateFormat = DateFormat('EEEE, MMMM d').format(now).toUpperCase();
    final dateSuffix = _getDaySuffix(now.day);
    final greeting = _displayName ?? 'Friend';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF000000)],
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHomeData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(dateFormat, dateSuffix, greeting),
                const SizedBox(height: 28),

                // Daily Tip
                _buildDailyTip(),
                const SizedBox(height: 40),

                // Tap to Tweak
                _buildTapToTweak(),
                const SizedBox(height: 48),

                // Today's Bites
                _buildTodaysBites(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'TH';
    switch (day % 10) {
      case 1:
        return 'ST';
      case 2:
        return 'ND';
      case 3:
        return 'RD';
      default:
        return 'TH';
    }
  }

  Widget _buildHeader(String dateFormat, String dateSuffix, String greeting) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$dateFormat$dateSuffix',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hello, $greeting',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ready to nourish yourself today?',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        // Chat icon
        GestureDetector(
          onTap: _openChat,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyTip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DAILY TIP',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3F5F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Colors.cyan[300],
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _dailyTip,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTapToTweak() {
    return Center(
      child: Column(
        children: [
          Text(
            'Tap to Tweak',
            style: TextStyle(
              color: Colors.purple[300],
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _openCamera,
            onLongPress: _showImageSourceDialog,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.purple.withValues(alpha: 0.6),
                    Colors.purple.withValues(alpha: 0.3),
                    Colors.purple.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                  stops: const [0.3, 0.5, 0.7, 1.0],
                ),
              ),
              child: Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.purple.shade400,
                        Colors.blue.shade600,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withValues(alpha: 0.5),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Snap a photo, describe, or\nspeak your meal',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaysBites() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "TODAY'S BITES",
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_suggestedBites.isEmpty && _todaysMeals.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                style: BorderStyle.solid,
              ),
            ),
            child: Center(
              child: Text(
                'No meals yet.\nTap the button above to start!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], height: 1.5),
              ),
            ),
          )
        else ...[
          // Show suggested bites first
          ...(_suggestedBites.map((bite) => _buildSuggestedBiteCard(bite))),
          // Then show logged meals
          if (_todaysMeals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              "LOGGED TODAY",
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            ...(_todaysMeals.map((meal) => _buildLoggedMealCard(meal))),
          ],
        ],
      ],
    );
  }

  Widget _buildSuggestedBiteCard(Map<String, dynamic> bite) {
    final suggestionId = bite['suggestion_id'] ?? '';
    final tweakOptions = List<String>.from(bite['tweak_options'] ?? []);
    final selectedSet = _selectedTweaks[suggestionId] ?? {};
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image placeholder (or real image if available)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade900, Colors.blue.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: bite['image_url'] != null
                  ? Image.network(
                      bite['image_url'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholderImage(bite),
                    )
                  : _buildPlaceholderImage(bite),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  bite['title'] ?? 'Healthy Meal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Tweak It section
                Row(
                  children: [
                    Icon(Icons.auto_fix_high, color: Colors.purple[300], size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'TWEAK IT',
                      style: TextStyle(
                        color: Colors.purple[300],
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                
                // Tweak option chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tweakOptions.map((tweak) {
                    final isSelected = selectedSet.contains(tweak);
                    return GestureDetector(
                      onTap: () => _toggleTweak(suggestionId, tweak),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? Colors.blue.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected 
                                ? Colors.blue[400]!
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              Icon(Icons.check_circle, color: Colors.blue[400], size: 16),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              tweak,
                              style: TextStyle(
                                color: isSelected ? Colors.blue[300] : Colors.white,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                
                Text(
                  'Select improvements to include in your recipe',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                
                // View Recipe button
                GestureDetector(
                  onTap: () => _tweakAndView(bite),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.restaurant_menu, color: Colors.purple[300], size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'View Recipe & Nutrition',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: Colors.grey[500], size: 20),
                      ],
                    ),
                  ),
                ),
                
                // Science note
                if (bite['science_note'] != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1218),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.science_outlined, color: Colors.orange[300], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'THE SCIENCE',
                              style: TextStyle(
                                color: Colors.orange[300],
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          bite['science_note'],
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage(Map<String, dynamic> bite) {
    final ingredients = List<String>.from(bite['key_ingredients'] ?? []);
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade800, Colors.blue.shade900],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant, color: Colors.white.withValues(alpha: 0.5), size: 40),
              if (ingredients.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  ingredients.take(3).join(' • '),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _toggleTweak(String suggestionId, String tweak) {
    setState(() {
      _selectedTweaks[suggestionId] ??= {};
      if (_selectedTweaks[suggestionId]!.contains(tweak)) {
        _selectedTweaks[suggestionId]!.remove(tweak);
      } else {
        _selectedTweaks[suggestionId]!.add(tweak);
      }
    });
  }

  Future<void> _tweakAndView(Map<String, dynamic> bite) async {
    final suggestionId = bite['suggestion_id'] ?? '';
    final selectedSet = _selectedTweaks[suggestionId] ?? {};
    
    // Save tweak selections as preferences
    if (selectedSet.isNotEmpty) {
      await _api.saveTweakSelection(
        suggestionId: suggestionId,
        selectedTweaks: selectedSet.toList(),
      );
    }
    
    // Build the meal text with selected tweaks
    String mealText = bite['title'] ?? 'Healthy Meal';
    if (selectedSet.isNotEmpty) {
      mealText = '$mealText with ${selectedSet.join(', ')}';
    }
    
    // Navigate to meal result with this as the base
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => MealResultScreen(
            mealText: mealText,
            onComplete: () {
              // Refresh suggestions after logging a meal
              _refreshSuggestions();
            },
          ),
        ),
      );
    }
  }

  Widget _buildLoggedMealCard(Map<String, dynamic> meal) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 50,
              height: 50,
              color: Colors.purple.shade900,
              child: meal['image_url'] != null
                  ? Image.network(meal['image_url'], fit: BoxFit.cover)
                  : Icon(Icons.restaurant, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal['title'] ?? 'Meal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (meal['nourish_tip'] != null)
                  Text(
                    meal['nourish_tip'],
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: Colors.green[400], size: 20),
        ],
      ),
    );
  }
}
