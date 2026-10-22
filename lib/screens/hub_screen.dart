import 'dart:async';
import 'package:flutter/material.dart';
import '../services/github_service.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  final _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    // Auto-Polling alle 4 Sekunden für neue Chatnachrichten vom GitHub Server
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchMessages(silent: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _scrollController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final msgs = await GitHubService().fetchChatMessages();
    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _msgController.clear();

    final success = await GitHubService().sendChatMessage(text);
    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        await _fetchMessages(silent: true);
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 60,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Senden über GitHub API.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = GitHubService().currentUser;

    return Column(
      children: [
        // Chat Header Status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF0F1420),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_done, size: 14, color: Color(0xFF00FFA3)),
                  const SizedBox(width: 6),
                  Text(
                    'Verbunden: ${GitHubService().repoName}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
                onPressed: () => _fetchMessages(),
                tooltip: 'Aktualisieren',
              ),
            ],
          ),
        ),

        // Message List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FFA3)))
              : _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade700),
                          const SizedBox(height: 12),
                          const Text(
                            'Noch keine Nachrichten',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Schreibe die erste Nachricht an deine Crew!',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg['author'] == currentUser;

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF00FFA3) : const Color(0xFF161E2E),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 0),
                                bottomRight: Radius.circular(isMe ? 0 : 16),
                              ),
                              border: Border.all(
                                color: isMe ? Colors.transparent : const Color(0xFF26344E),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Text(
                                    msg['author'] ?? 'Anonymous',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6366F1),
                                    ),
                                  ),
                                Text(
                                  msg['text'] ?? '',
                                  style: TextStyle(
                                    color: isMe ? Colors.black : Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),

        // Bottom Input Field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF0F1420),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Nachricht eingeben...',
                      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF161E2E),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FFA3)),
                        )
                      : const Icon(Icons.send_rounded, color: Color(0xFF00FFA3)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
