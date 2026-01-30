import 'package:flutter/material.dart';
import '../../services/api_client.dart';

class ChatDrawer extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const ChatDrawer({super.key, this.onProfileUpdated});

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _hasProfile = false;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    setState(() => _isLoading = true);

    try {
      final response = await _api.getChatHistory();

      if (response.ok && response.data != null) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response.data['messages'] ?? []);
          _hasProfile = response.data['has_profile'] ?? false;
          _displayName = response.data['display_name'];
        });

        // If no messages and no profile, add welcome message
        if (_messages.isEmpty) {
          _addWelcomeMessage();
        }
      }
    } catch (e) {
      _addWelcomeMessage();
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _addWelcomeMessage() {
    // This will be replaced by the first API call response
    setState(() {
      _messages = [
        {
          'role': 'assistant',
          'content': _hasProfile
              ? "Hi${_displayName != null ? ' $_displayName' : ''}! How can I help you eat healthier today?"
              : "Hi there! I'm your nutrition assistant. I'd love to get to know you better so I can give personalized advice. What's your name?",
          'timestamp': DateTime.now().toIso8601String(),
        }
      ];
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    _msgController.clear();
    
    // Add user message immediately
    setState(() {
      _messages.add({
        'role': 'user',
        'content': text,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final response = await _api.sendChatMessage(message: text);

      if (response.ok && response.data != null) {
        final message = response.data['message'];
        final profileChanged = response.data['profile_changed'] ?? false;

        setState(() {
          _messages.add({
            'role': message['role'],
            'content': message['content'],
            'timestamp': message['timestamp'],
          });
        });

        // If profile was updated, notify parent to refresh
        if (profileChanged && widget.onProfileUpdated != null) {
          widget.onProfileUpdated!();
          
          // Update local state
          final updatedProfile = response.data['updated_profile'];
          if (updatedProfile != null) {
            setState(() {
              _displayName = updatedProfile['display_name'];
              _hasProfile = _displayName != null;
            });
          }
        }
      } else {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': "Sorry, I'm having trouble connecting. Please try again.",
            'timestamp': DateTime.now().toIso8601String(),
          });
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': "Connection error. Make sure the backend is running.",
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
    } finally {
      setState(() => _isSending = false);
      _scrollToBottom();
    }
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.assistant, color: Colors.purple, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nutrition Assistant',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _hasProfile ? 'Here to help you eat better' : 'Let\'s get to know each other',
                            style: TextStyle(color: Colors.grey[400], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              
              const Divider(color: Colors.white12, height: 1),
              
              // Messages
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          return _buildMessage(msg);
                        },
                      ),
              ),
              
              // Typing indicator
              if (_isSending)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTypingDot(0),
                            _buildTypingDot(1),
                            _buildTypingDot(2),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Quick suggestion chips
              if (_messages.length > 1 && !_isSending)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildQuickChip('Suggest a healthy breakfast'),
                      _buildQuickChip('High-protein meal ideas'),
                      _buildQuickChip('Quick 15-min recipes'),
                      _buildQuickChip('Help me eat more vegetables'),
                    ],
                  ),
                ),
              
              // Input area
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: TextField(
                            controller: _msgController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _hasProfile ? 'Ask me anything...' : 'Tell me about yourself...',
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _sendMessage(),
                            maxLines: null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.purple, Colors.blue.shade700],
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(Icons.send, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser 
              ? Colors.purple.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
          border: Border.all(
            color: isUser 
                ? Colors.purple.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          msg['content'] ?? '',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 150)),
      builder: (context, value, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[400],
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildQuickChip(String text) {
    return GestureDetector(
      onTap: () {
        _msgController.text = text;
        _sendMessage();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_fix_high, color: Colors.purple[300], size: 14),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: Colors.purple[200],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
