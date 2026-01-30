import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_client.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _reflectionController = TextEditingController();

  bool _isLoading = true;
  String _weekOf = '';
  List<Map<String, dynamic>> _reflections = [];
  int _reflectionCount = 0;
  String _wisdomSummary = '';
  List<String> _wisdomTips = [];
  List<Map<String, dynamic>> _meals = [];
  
  // Track expanded meal
  String? _expandedMealId;
  
  // Check-in state
  double _feelingValue = 0.5; // 0 = Challenging, 1 = Great
  bool _isSavingCheckIn = false;

  @override
  void initState() {
    super.initState();
    _loadJournalData();
  }

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  Future<void> _loadJournalData() async {
    setState(() => _isLoading = true);

    try {
      final response = await _api.getWeeklyJournal();

      if (response.ok && response.data != null) {
        setState(() {
          _weekOf = response.data['week_of'] ?? '';
          _reflections = List<Map<String, dynamic>>.from(
              response.data['reflections'] ?? []);
          _reflectionCount = response.data['reflection_count'] ?? 0;
          _meals = List<Map<String, dynamic>>.from(
              response.data['meals'] ?? []);
          
          final wisdom = response.data['wisdom'] as Map<String, dynamic>?;
          if (wisdom != null) {
            _wisdomSummary = wisdom['summary'] ?? '';
            _wisdomTips = List<String>.from(wisdom['tips'] ?? []);
          }
        });
      }
    } catch (e) {
      setState(() {
        _wisdomSummary = "Every meal is a chance to nourish yourself!";
        _wisdomTips = [
          "Add leafy greens to one meal today",
          "Drink water before meals",
          "Try a new healthy recipe",
          "Eat mindfully without distractions",
        ];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showAddReflectionDialog() {
    _reflectionController.clear();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1F2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              const Text(
                'Add Reflection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'How was your week? Share your thoughts about your eating habits.',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
              const SizedBox(height: 20),
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1218),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _reflectionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'e.g., "Ate a lot of junk food this week"',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade400, Colors.blue.shade600],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: () => _submitReflection(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_rounded, size: 20),
                        SizedBox(width: 8),
                        Text('Save Reflection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String _getFeelingText(double value) {
    if (value < 0.2) return 'Struggling';
    if (value < 0.4) return 'Challenging';
    if (value < 0.6) return 'Okay';
    if (value < 0.8) return 'Good';
    return 'Great!';
  }

  Color _getFeelingColor(double value) {
    if (value < 0.2) return Colors.red[400]!;
    if (value < 0.4) return Colors.orange[400]!;
    if (value < 0.6) return Colors.yellow[600]!;
    if (value < 0.8) return Colors.lightGreen[400]!;
    return Colors.green[400]!;
  }

  Future<void> _saveCheckIn() async {
    final text = _reflectionController.text.trim();
    
    // Build reflection text with feeling
    final feelingLabel = _getFeelingText(_feelingValue).toLowerCase().replaceAll('!', '');
    
    final checkInText = text.isNotEmpty
        ? 'Feeling: $feelingLabel. Proud of: $text'
        : 'Feeling: $feelingLabel this week.';
    
    setState(() => _isSavingCheckIn = true);

    try {
      final response = await _api.addReflection(text: checkInText);
      
      if (response.ok) {
        _reflectionController.clear();
        setState(() => _feelingValue = 0.5);
        _loadJournalData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Check-in saved!'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception(response.errorMessage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingCheckIn = false);
      }
    }
  }

  Future<void> _submitReflection(BuildContext dialogContext) async {
    final text = _reflectionController.text.trim();
    if (text.isEmpty) return;

    Navigator.pop(dialogContext);

    try {
      final response = await _api.addReflection(text: text);
      
      if (response.ok) {
        _loadJournalData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reflection saved!'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception(response.errorMessage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitMealFeedback(String mealId, bool helpful) async {
    try {
      await _api.submitFeedback(mealId: mealId, liked: helpful);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(helpful ? 'Thanks for the feedback!' : 'We\'ll improve our suggestions'),
            backgroundColor: helpful ? Colors.green : Colors.grey,
          ),
        );
      }
    } catch (e) {
      // Silent fail
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF000000)],
        ),
      ),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadJournalData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Journal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 28),

                      _buildWeeklyCheckIn(),
                      const SizedBox(height: 28),

                      _buildWeeklyWisdom(),
                      const SizedBox(height: 28),

                      _buildMealHistory(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildWeeklyCheckIn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.fact_check_outlined, color: Colors.blue[300], size: 20),
            const SizedBox(width: 8),
            Text(
              'WEEKLY CHECK-IN',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Question 1: Feeling slider
              const Text(
                'How did you feel about your progress this week?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              
              // Current feeling text
              Center(
                child: Text(
                  _getFeelingText(_feelingValue),
                  style: TextStyle(
                    color: _getFeelingColor(_feelingValue),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              
              // Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _getFeelingColor(_feelingValue),
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: _getFeelingColor(_feelingValue),
                  overlayColor: _getFeelingColor(_feelingValue).withValues(alpha: 0.2),
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                ),
                child: Slider(
                  value: _feelingValue,
                  onChanged: (value) {
                    setState(() => _feelingValue = value);
                  },
                ),
              ),
              
              // Labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Challenging',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    Text(
                      'Great',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Question 2: Text input
              const Text(
                "What's one thing you're proud of?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1218),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _reflectionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g., Ate more vegetables this week...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSavingCheckIn ? null : _saveCheckIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSavingCheckIn
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'SAVE CHECK-IN',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyWisdom() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.orange[400], size: 20),
            const SizedBox(width: 8),
            Text(
              'WEEKLY WISDOM',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WEEK OF $_weekOf',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              
              Text(
                _wisdomSummary,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              
              Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Icon(Icons.trending_up_rounded, color: Colors.cyan[300], size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'TRY THIS WEEK',
                    style: TextStyle(
                      color: Colors.cyan[300],
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              ...List.generate(_wisdomTips.length, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}.',
                        style: TextStyle(color: Colors.cyan[300], fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _wisdomTips[index],
                          style: TextStyle(color: Colors.grey[400], fontSize: 14, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMealHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_rounded, color: Colors.purple[300], size: 20),
            const SizedBox(width: 8),
            Text(
              'MEAL HISTORY',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        if (_meals.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                'No meals logged this week.\nStart tracking from the home screen!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], height: 1.5),
              ),
            ),
          )
        else
          // Timeline with meals
          ...List.generate(_meals.length, (index) {
            final meal = _meals[index];
            final mealId = meal['meal_id'] ?? index.toString();
            final isExpanded = _expandedMealId == mealId;
            
            return _buildMealCard(meal, mealId, isExpanded, isLast: index == _meals.length - 1);
          }),
      ],
    );
  }

  Widget _buildMealCard(Map<String, dynamic> meal, String mealId, bool isExpanded, {bool isLast = false}) {
    final title = meal['title'] ?? 'Meal';
    final createdAt = meal['created_at'] as String?;
    final imageUrl = meal['image_url'] as String?;
    String timeStr = '';
    if (createdAt != null) {
      try {
        final date = DateTime.parse(createdAt);
        timeStr = DateFormat('h:mm a').format(date);
      } catch (_) {}
    }
    
    final betterBite = meal['better_bite'] ?? 'Add more protein to feel fuller longer.';
    final theScience = meal['the_science'] ?? 'Protein stabilizes blood sugar and reduces hunger.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.blue[400],
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: isExpanded ? 450 : 80,
                color: Colors.blue[400]?.withValues(alpha: 0.3),
              ),
          ],
        ),
        const SizedBox(width: 16),
        
        // Meal card
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(16),
              border: isExpanded 
                  ? Border.all(color: Colors.purple.withValues(alpha: 0.3), width: 1)
                  : null,
            ),
            child: Column(
              children: [
                // Header (always visible)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _expandedMealId = isExpanded ? null : mealId;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Meal thumbnail with image
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl != null
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(Icons.restaurant, color: Colors.grey[600], size: 24),
                                  )
                                : Icon(Icons.restaurant, color: Colors.grey[600], size: 24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                timeStr,
                                style: TextStyle(color: Colors.grey[500], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.grey[500],
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Expanded content
                if (isExpanded) ...[
                  // Large image
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                    ),
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(Icons.image, color: Colors.grey[700], size: 48),
                            ),
                          )
                        : Center(
                            child: Icon(Icons.image, color: Colors.grey[700], size: 48),
                          ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Meal',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Better Bite
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
                                  Icon(Icons.lightbulb_outline, color: Colors.purple[300], size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'BETTER BITE',
                                    style: TextStyle(
                                      color: Colors.purple[300],
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                betterBite,
                                style: TextStyle(color: Colors.grey[300], fontSize: 14, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // View Recipe button
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1218),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.restaurant_menu, color: Colors.purple[300], size: 18),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'View Recipe & Nutrition',
                                  style: TextStyle(color: Colors.white, fontSize: 14),
                                ),
                              ),
                              Icon(Icons.chevron_right, color: Colors.grey[500]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // The Science
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
                                  Icon(Icons.science_outlined, color: Colors.blue[300], size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'THE SCIENCE',
                                    style: TextStyle(
                                      color: Colors.blue[300],
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                theScience,
                                style: TextStyle(color: Colors.grey[400], fontSize: 14, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Feedback (Was this helpful?)
                if (!isExpanded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Was this helpful?',
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _submitMealFeedback(mealId, true),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.thumb_up_outlined, color: Colors.grey[500], size: 18),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _submitMealFeedback(mealId, false),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.thumb_down_outlined, color: Colors.grey[500], size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
