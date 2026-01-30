import 'package:flutter/material.dart';

import '../../services/api_client.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _preferences = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final response = await _api.getUserSummary();

      if (response.ok && response.data != null) {
        setState(() {
          _preferences = List<Map<String, dynamic>>.from(
              response.data['top_preferences'] ?? []);
        });
      }

      // Also load home data to get profile
      final homeResponse = await _api.getHomeData();
      if (homeResponse.ok && homeResponse.data != null) {
        // Extract what we can
        setState(() {
          _profile = {
            'display_name': homeResponse.data['user']?['display_name'],
            'has_profile': homeResponse.data['user']?['has_profile'] ?? false,
          };
        });
      }
    } catch (e) {
      // Handle error
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _profile?['display_name'] ?? 'Friend';
    final hasProfile = _profile?['has_profile'] ?? false;

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
                onRefresh: _loadProfile,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      const Text(
                        'Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your preferences and settings',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Profile card
                      _buildProfileCard(displayName, hasProfile),
                      const SizedBox(height: 24),

                      // Learned preferences
                      _buildPreferencesSection(),
                      const SizedBox(height: 24),

                      // Info
                      _buildInfoSection(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildProfileCard(String displayName, bool hasProfile) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.blue.shade600],
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasProfile
                      ? 'Profile complete'
                      : 'Chat with the assistant to set up your profile',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LEARNED PREFERENCES',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (_preferences.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                'No preferences learned yet.\nLog meals and give feedback to help me learn!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], height: 1.5),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: _preferences.map((pref) {
                final factKey = pref['fact_key'] as String? ?? '';
                final strength = (pref['strength'] as num?)?.toDouble() ?? 0.0;

                // Parse fact key (e.g., "likes:chicken" -> "Likes chicken")
                String displayText = factKey;
                IconData icon = Icons.star;
                Color color = Colors.grey;

                if (factKey.startsWith('likes:')) {
                  displayText = 'Likes ${factKey.substring(6)}';
                  icon = Icons.favorite;
                  color = Colors.green;
                } else if (factKey.startsWith('dislikes:')) {
                  displayText = 'Dislikes ${factKey.substring(9)}';
                  icon = Icons.thumb_down;
                  color = Colors.red;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Strength indicator
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${(strength * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ABOUT',
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
          child: Column(
            children: [
              _buildInfoRow(Icons.info_outline, 'Tweak My Meal', 'v1.0.0'),
              const Divider(color: Colors.white12, height: 24),
              _buildInfoRow(Icons.chat_bubble_outline, 'Chat with assistant',
                  'Update preferences'),
              const Divider(color: Colors.white12, height: 24),
              _buildInfoRow(
                  Icons.lightbulb_outline, 'Powered by AI', 'OpenAI GPT-4'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[500], size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
