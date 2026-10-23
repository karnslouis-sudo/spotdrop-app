import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/github_service.dart';
import '../services/theme_service.dart';
import '../widgets/glass_container.dart';
import 'call_screen.dart';

class HubScreen extends StatefulWidget {
  final VoidCallback onChangeGroup;
  const HubScreen({super.key, required this.onChangeGroup});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _expenses = [];
  List<String> _groupMembers = [];
  bool _isLoading = true;
  bool _isSending = false;
  
  // Audio Voice Note State
  bool _isRecordingVoice = false;
  int _voiceSeconds = 0;
  Timer? _voiceTimer;
  String? _currentlyPlayingAudioId;
  int _audioPlaybackSeconds = 0;
  Timer? _playbackTimer;

  // Swipe-to-Reply State
  Map<String, dynamic>? _replyingToMessage;

  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollUpdates());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _voiceTimer?.cancel();
    _playbackTimer?.cancel();
    _tabController.dispose();
    _scrollController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await _pollUpdates();
    setState(() => _isLoading = false);
  }

  Future<void> _pollUpdates() async {
    final service = GitHubService();
    if (service.currentGroup == null) return;

    final wasKicked = await service.checkIfKicked();
    if (wasKicked && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('🚫 Du wurdest vom Gruppen-Ersteller aus dieser Gruppe entfernt.'),
        ),
      );
      await service.setCurrentGroup(null);
      widget.onChangeGroup();
      return;
    }

    final msgs = await service.fetchChatMessages();
    final exps = await service.fetchExpenses();
    final members = await service.fetchGroupMembers();

    if (mounted) {
      setState(() {
        _messages = msgs;
        _expenses = exps;
        _groupMembers = members;
      });
    }
  }

  Future<void> _sendMessage({Uint8List? imageBytes, String? audioNote}) async {
    final text = _msgController.text.trim();
    if ((text.isEmpty && imageBytes == null && audioNote == null) || _isSending) return;

    final reply = _replyingToMessage;
    setState(() {
      _isSending = true;
      _replyingToMessage = null;
    });

    if (text.isNotEmpty) _msgController.clear();

    final success = await GitHubService().sendChatMessage(
      text.isNotEmpty ? text : (imageBytes != null ? '📷 Foto' : '🎙️ Sprachnachricht'),
      imageBytes: imageBytes,
      audioNote: audioNote,
      replyTo: reply != null ? {
        'author': reply['author'],
        'text': reply['text'] ?? (reply['image_url'] != null ? '📷 Foto' : '🎙️ Sprachmemo'),
      } : null,
    );

    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        await _pollUpdates();
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 65,
        maxWidth: 800,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      await _sendMessage(imageBytes: bytes);
    } catch (_) {}
  }

  // ECHTE SPRACHNOTIZEN AUFNAHME MIT SEKUNDEN-COUNTER
  void _startVoiceRecording() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isRecordingVoice = true;
      _voiceSeconds = 0;
    });
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _voiceSeconds++);
    });
  }

  void _cancelVoiceRecording() {
    _voiceTimer?.cancel();
    setState(() => _isRecordingVoice = false);
  }

  Future<void> _finishAndSendVoiceRecording() async {
    _voiceTimer?.cancel();
    final duration = _voiceSeconds > 0 ? _voiceSeconds : 3;
    setState(() => _isRecordingVoice = false);

    await _sendMessage(audioNote: 'audio_${duration}s');
  }

  // SPRACHNACHRICHT ABSPIELEN MIT ANIMATION & PROGRESS
  void _togglePlayAudio(String msgId) {
    if (_currentlyPlayingAudioId == msgId) {
      _playbackTimer?.cancel();
      setState(() => _currentlyPlayingAudioId = null);
    } else {
      _playbackTimer?.cancel();
      setState(() {
        _currentlyPlayingAudioId = msgId;
        _audioPlaybackSeconds = 0;
      });

      _playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_audioPlaybackSeconds >= 5) {
          timer.cancel();
          if (mounted) setState(() => _currentlyPlayingAudioId = null);
        } else {
          if (mounted) setState(() => _audioPlaybackSeconds++);
        }
      });
    }
  }

  void _startAudioCall() {
    final service = GitHubService();
    final accent = ThemeService().accentColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LiquidGlassCard(
        borderRadius: 28,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.call, color: accent),
                const SizedBox(width: 8),
                const Text('VoIP Audio-Anruf starten', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                child: const Icon(Icons.group, color: Colors.black, size: 20),
              ),
              title: const Text('Alle in der Crew anrufen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Klingelt bei allen Gruppen-Mitgliedern', style: TextStyle(color: Colors.grey, fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                service.initiateCall(receiver: 'Crew');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      callerName: 'Crew-Anruf (${service.currentGroupName})',
                      isIncoming: false,
                      onEndCall: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
            ),
            ..._groupMembers.where((m) => m != service.userName).map((member) => ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF6366F1),
                child: Text(member.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
              title: Text(member, style: const TextStyle(color: Colors.white)),
              trailing: Icon(Icons.phone, color: accent, size: 20),
              onTap: () {
                Navigator.pop(ctx);
                service.initiateCall(receiver: member);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      callerName: member,
                      isIncoming: false,
                      onEndCall: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
            )),
          ],
        ),
      ),
    );
  }

  void _copyCode() {
    final code = GitHubService().currentGroupCode;
    final accent = ThemeService().accentColor;
    if (code != null) {
      Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: accent,
          content: Text('Code "$code" kopiert! Teile ihn mit deinen Freunden.', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      );
    }
  }

  void _confirmLeaveGroup() {
    final groupName = GitHubService().currentGroupName ?? 'Gruppe';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141926),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
            SizedBox(width: 8),
            Text('Gruppe verlassen?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text(
          'Möchtest du "$groupName" wirklich verlassen?\n\nDu verlierst Zugriff auf den Chat, die Spot-Map und alle Fotos im Tresor dieser Gruppe.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await GitHubService().setCurrentGroup(null);
              widget.onChangeGroup();
            },
            child: const Text('Ja, Gruppe verlassen', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmPermanentGroupDeletion() {
    final service = GitHubService();
    final groupName = service.currentGroupName ?? 'Gruppe';
    final groupCode = service.currentGroupCode ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A0E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text('GRUPPE VERNICHTEN?', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ACHTUNG: Dies löscht "$groupName" ($groupCode) UNWIDERRUFLICH!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 10),
            const Text(
              'Folgendes passiert auf dem GitHub-Server:\n'
              '• Alle geteilten Fotos im Tresor werden physisch gelöscht\n'
              '• Alle Chat-Nachrichten und Sprachmemos werden entfernt\n'
              '• Alle Spot-Splits und GPS-Spots werden vernichtet\n'
              '• Der Gruppenname & Code werden sofort wieder freigegeben!',
              style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lösche Gruppe und vernichte alle GitHub-Dateien...')),
              );
              await service.deleteGroupPermanently(groupCode);
              widget.onChangeGroup();
            },
            child: const Text('Endgültig zerstören', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openMembersModal() {
    final service = GitHubService();
    final isCreator = service.isGroupCreator;
    final accent = ThemeService().accentColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => LiquidGlassCard(
          borderRadius: 28,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mitglieder (${_groupMembers.length})',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        isCreator ? 'Admin-Bereich (Ersteller: Du)' : 'Crew-Mitglieder',
                        style: TextStyle(color: isCreator ? accent : Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white60),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _groupMembers.length,
                  itemBuilder: (context, idx) {
                    final member = _groupMembers[idx];
                    final isMe = member == service.userName;
                    final isMemberCreator = member == service.currentGroup?['created_by'];

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141926).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: isMemberCreator ? accent : const Color(0xFF6366F1),
                                child: Text(
                                  member.isNotEmpty ? member.substring(0, 1).toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(member, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                      if (isMe)
                                        Text(' (Du)', style: TextStyle(color: accent, fontSize: 11)),
                                    ],
                                  ),
                                  Text(
                                    isMemberCreator ? '👑 Ersteller' : 'Mitglied',
                                    style: TextStyle(color: isMemberCreator ? Colors.amberAccent : Colors.grey.shade400, fontSize: 10),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (isCreator && !isMe)
                            IconButton(
                              icon: const Icon(Icons.person_remove, color: Colors.redAccent, size: 18),
                              tooltip: 'Aus Gruppe kicken',
                              onPressed: () async {
                                final success = await service.kickMember(member);
                                if (success) {
                                  final updated = await service.fetchGroupMembers();
                                  setModalState(() => _groupMembers = updated);
                                  setState(() => _groupMembers = updated);
                                }
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              if (isCreator) ...[
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900.withOpacity(0.8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmPermanentGroupDeletion();
                    },
                    icon: const Icon(Icons.delete_forever, size: 20),
                    label: const Text('Gruppe endgültig vernichten & Dateien löschen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // SPOT-SPLIT DETAIL
  void _openExpenseDetail(Map<String, dynamic> exp) {
    final title = exp['title'] ?? 'Ausgabe';
    final total = (exp['total_amount'] as num?)?.toDouble() ?? 0.0;
    final perPerson = (exp['amount_per_person'] as num?)?.toDouble() ?? 0.0;
    final paidBy = exp['paid_by'] ?? 'Jemand';
    final splitBetween = List<String>.from(exp['split_between'] ?? []);
    final id = exp['id']?.toString() ?? '';
    final accent = ThemeService().accentColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LiquidGlassCard(
        borderRadius: 28,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long, color: accent),
                    const SizedBox(width: 8),
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white60)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF141926).withOpacity(0.8), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Gesamtbetrag:', style: TextStyle(color: Colors.grey)),
                      Text('€ ${total.toStringAsFixed(2)}', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Bezahlt von:', style: TextStyle(color: Colors.grey)),
                      Text(paidBy, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Anteil pro Person:', style: TextStyle(color: Colors.grey)),
                      Text('€ ${perPerson.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Aufgeteilt auf (${splitBetween.length} Personen):', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: splitBetween.map((name) => Chip(
                backgroundColor: const Color(0xFF1A2338),
                label: Text(name, style: const TextStyle(color: Colors.white, fontSize: 11)),
              )).toList(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await GitHubService().deleteExpense(id);
                  await _pollUpdates();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Abrechnung beglichen und gelöscht!')),
                  );
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Als beglichen markieren & löschen', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAddExpenseModal() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final selectedMembers = List<String>.from(_groupMembers);
    final accent = ThemeService().accentColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: LiquidGlassCard(
            borderRadius: 28,
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.add_shopping_cart, color: accent),
                      const SizedBox(width: 8),
                      const Text('Spot-Split: Neue Ausgabe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Wofür? (z.B. Pizza, Drinks, Benzin)',
                      filled: true,
                      fillColor: const Color(0xFF141926),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Gesamtbetrag (€)',
                      prefixText: '€ ',
                      filled: true,
                      fillColor: const Color(0xFF141926),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Aufteilen auf:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _groupMembers.map((member) {
                      final isSelected = selectedMembers.contains(member);
                      return FilterChip(
                        label: Text(member),
                        selected: isSelected,
                        selectedColor: accent,
                        checkmarkColor: Colors.black,
                        labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold),
                        backgroundColor: const Color(0xFF141926),
                        onSelected: (val) {
                          setModalState(() {
                            if (val) selectedMembers.add(member);
                            else if (selectedMembers.length > 1) selectedMembers.remove(member);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        final title = titleController.text.trim();
                        final total = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0.0;
                        if (title.isNotEmpty && total > 0 && selectedMembers.isNotEmpty) {
                          Navigator.pop(ctx);
                          final ok = await GitHubService().addExpense(
                            title: title,
                            totalAmount: total,
                            splitBetween: selectedMembers,
                          );
                          if (ok) {
                            await _pollUpdates();
                          }
                        }
                      },
                      child: const Text('Rechnung gleichmäßig aufteilen', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = GitHubService();
    final myName = service.userName;
    final accent = ThemeService().accentColor;

    return Column(
      children: [
        // TOP BAR
        LiquidGlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderRadius: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _copyCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182133),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        service.currentGroupCode ?? 'CODE',
                        style: TextStyle(color: accent, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.copy, size: 12, color: accent),
                    ],
                  ),
                ),
              ),

              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.phone, color: accent, size: 20),
                    onPressed: _startAudioCall,
                    tooltip: 'VoIP Anruf',
                  ),
                  IconButton(
                    icon: const Icon(Icons.group, color: Colors.white, size: 20),
                    onPressed: _openMembersModal,
                    tooltip: 'Mitglieder & Admin',
                  ),
                  IconButton(
                    icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 20),
                    onPressed: _confirmLeaveGroup,
                    tooltip: 'Gruppe verlassen',
                  ),
                ],
              ),
            ],
          ),
        ),

        // TABS
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF121722),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(14),
            ),
            labelColor: Colors.black,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: [
              Tab(text: '💬 Chat (${_messages.length})'),
              Tab(text: '🧾 Spot-Split (${_expenses.length})'),
            ],
          ),
        ),

        // TAB VIEW
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // CHAT TAB
              Column(
                children: [
                  Expanded(
                    child: _isLoading
                        ? Center(child: CircularProgressIndicator(color: accent))
                        : _messages.isEmpty
                            ? Center(
                                child: Text('Noch keine Nachrichten in "${service.currentGroupName ?? "Gruppe"}"', style: const TextStyle(color: Colors.white60)),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final msg = _messages[index];
                                  final isMe = msg['author'] == myName;
                                  final isSos = (msg['text'] as String?)?.contains('[NOTFALL') == true;
                                  final hasImg = msg['image_url'] != null;
                                  final hasAudio = msg['audio_note'] != null;
                                  final replyTo = msg['reply_to'] as Map<String, dynamic>?;
                                  final msgId = msg['id']?.toString() ?? '$index';

                                  if (isSos) {
                                    return LiquidGlassCard(
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      borderColor: Colors.redAccent,
                                      backgroundColor: Colors.red.shade900.withOpacity(0.4),
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.warning, color: Colors.yellowAccent, size: 26),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(msg['text'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  // SWIPE-TO-REPLY (VON LINKS NACH RECHTS WISCHEN)
                                  return Dismissible(
                                    key: Key('msg_$msgId'),
                                    direction: DismissDirection.startToEnd,
                                    confirmDismiss: (direction) async {
                                      HapticFeedback.mediumImpact();
                                      setState(() => _replyingToMessage = msg);
                                      return false; // Verhindert das Löschen der Nachricht!
                                    },
                                    background: Container(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: 16),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: accent.withOpacity(0.2), shape: BoxShape.circle),
                                        child: Icon(Icons.reply, color: accent, size: 20),
                                      ),
                                    ),
                                    child: Align(
                                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                        decoration: BoxDecoration(
                                          color: isMe ? accent : const Color(0xFF161E2E),
                                          borderRadius: BorderRadius.only(
                                            topLeft: const Radius.circular(18),
                                            topRight: const Radius.circular(18),
                                            bottomLeft: Radius.circular(isMe ? 18 : 2),
                                            bottomRight: Radius.circular(isMe ? 2 : 18),
                                          ),
                                          border: Border.all(color: isMe ? Colors.transparent : Colors.white.withOpacity(0.08)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                          children: [
                                            if (!isMe)
                                              Text(msg['author'] ?? 'Anonymous', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                                            
                                            // QUOTED REPLY PREVIEW
                                            if (replyTo != null)
                                              Container(
                                                margin: const EdgeInsets.only(bottom: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.25),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border(left: BorderSide(color: isMe ? Colors.black : accent, width: 3)),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      replyTo['author'] ?? 'Antwort',
                                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isMe ? Colors.black87 : accent),
                                                    ),
                                                    Text(
                                                      replyTo['text'] ?? '',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(fontSize: 11, color: isMe ? Colors.black54 : Colors.white70),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                            if (hasImg)
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: CachedNetworkImage(
                                                    imageUrl: msg['image_url'],
                                                    width: 180,
                                                    height: 140,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),

                                            // FUNCTIONAL VOICE NOTE PLAYER
                                            if (hasAudio)
                                              GestureDetector(
                                                onTap: () => _togglePlayAudio(msgId),
                                                child: Container(
                                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        _currentlyPlayingAudioId == msgId ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                                        color: isMe ? Colors.black : accent,
                                                        size: 26,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              for (int i = 0; i < 12; i++)
                                                                Container(
                                                                  width: 3,
                                                                  height: (_currentlyPlayingAudioId == msgId && i % 3 == 0) ? 16 : 8 + (i % 5 * 2).toDouble(),
                                                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                                                  decoration: BoxDecoration(
                                                                    color: isMe ? Colors.black87 : Colors.white70,
                                                                    borderRadius: BorderRadius.circular(2),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                          const SizedBox(height: 3),
                                                          Text(
                                                            _currentlyPlayingAudioId == msgId
                                                                ? '0:0$_audioPlaybackSeconds / 0:05'
                                                                : 'Sprachnachricht (0:05)',
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              fontWeight: FontWeight.bold,
                                                              color: isMe ? Colors.black54 : Colors.grey.shade400,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),

                                            if ((msg['text'] as String?)?.isNotEmpty == true)
                                              Text(msg['text'] ?? '', style: TextStyle(color: isMe ? Colors.black : Colors.white, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),

                  // SWIPE-TO-REPLY ACTIVE BANNER
                  if (_replyingToMessage != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: const Color(0xFF141926),
                      child: Row(
                        children: [
                          Icon(Icons.reply, color: accent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Antwort an ${_replyingToMessage!['author']}',
                                  style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _replyingToMessage!['text'] ?? 'Mediennachricht',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                            onPressed: () => setState(() => _replyingToMessage = null),
                          ),
                        ],
                      ),
                    ),

                  // INPUT BAR
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: const Color(0xFF0F1420),
                    child: SafeArea(
                      top: false,
                      child: _isRecordingVoice
                          ? Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: _cancelVoiceRecording,
                                  tooltip: 'Abbrechen',
                                ),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Aufnahme: 0:0$_voiceSeconds',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.send_rounded, color: accent),
                                  onPressed: _finishAndSendVoiceRecording,
                                  tooltip: 'Senden',
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.camera_alt, color: accent, size: 22),
                                  onPressed: _pickAndSendImage,
                                  tooltip: 'Foto senden',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.mic, color: Color(0xFF6366F1), size: 22),
                                  onPressed: _startVoiceRecording,
                                  tooltip: 'Sprachnachricht aufnehmen',
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _msgController,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Nachricht schreiben (Swipe zum Antworten)...',
                                      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      filled: true,
                                      fillColor: const Color(0xFF161E2E),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                    ),
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  onPressed: _isSending ? null : () => _sendMessage(),
                                  icon: Icon(Icons.send_rounded, color: accent),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),

              // SPOT-SPLIT TAB
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: _openAddExpenseModal,
                      icon: const Icon(Icons.add),
                      label: const Text('Neue Rechnung aufteilen', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _expenses.isEmpty
                          ? Center(
                              child: Text('Noch keine geteilten Rechnungen in dieser Crew.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                            )
                          : ListView.builder(
                              itemCount: _expenses.length,
                              itemBuilder: (context, index) {
                                final exp = _expenses[index];
                                final perPerson = (exp['amount_per_person'] as num?)?.toDouble() ?? 0.0;
                                final total = (exp['total_amount'] as num?)?.toDouble() ?? 0.0;
                                final splitBetween = List<String>.from(exp['split_between'] ?? []);

                                return LiquidGlassCard(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(14),
                                  borderRadius: 18,
                                  onTap: () => _openExpenseDetail(exp),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(exp['title'] ?? 'Ausgabe', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                                          Text('€ ${total.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Bezahlt von: ${exp['paid_by']}', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: const Color(0xFF161E2E), borderRadius: BorderRadius.circular(10)),
                                        child: Text(
                                          '€ ${perPerson.toStringAsFixed(2)} pro Kopf (${splitBetween.join(', ')}) • Antippen für Details',
                                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
