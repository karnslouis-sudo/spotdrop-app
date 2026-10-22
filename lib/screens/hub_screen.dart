import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/github_service.dart';
import '../widgets/glass_container.dart';

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
  
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _expenses = [];
  List<String> _groupMembers = [];
  bool _isLoading = true;
  bool _isSending = false;
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

    // Prüfen, ob der Nutzer gekickt wurde
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

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _msgController.clear();

    final success = await GitHubService().sendChatMessage(text);
    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        await _pollUpdates();
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 60,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    }
  }

  void _copyCode() {
    final code = GitHubService().currentGroupCode;
    if (code != null) {
      Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00FFA3),
          content: Text('Code "$code" kopiert! Teile ihn mit deinen Freunden.', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      );
    }
  }

  // DIALOG: BESTÄTIGUNG ZUM VERLASSEN DER GRUPPE (SICHERHEITSABFRAGE)
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
            child: const Text('Abbrechen (Hierbleiben)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
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

  // DIALOG: MITGLIEDERLISTE & KICK-FUNKTION (NUR FÜR ERSTELLER)
  void _openMembersModal() {
    final service = GitHubService();
    final isCreator = service.isGroupCreator;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101522),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
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
                      const Text('👥 Crew-Mitglieder', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(
                        isCreator ? '👑 Du bist der Ersteller dieser Gruppe (Admin)' : 'Mitglieder in dieser Gruppe',
                        style: TextStyle(fontSize: 11, color: isCreator ? const Color(0xFF00FFA3) : Colors.grey),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _groupMembers.length,
                  itemBuilder: (context, index) {
                    final member = _groupMembers[index];
                    final isMe = member == service.userName;
                    final isOwner = member == service.currentGroup?['created_by'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161E2E),
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
                                backgroundColor: isOwner ? const Color(0xFF00FFA3) : const Color(0xFF6366F1),
                                child: Text(
                                  member.substring(0, 1).toUpperCase(),
                                  style: TextStyle(color: isOwner ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$member ${isMe ? "(Du)" : ""}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  if (isOwner)
                                    const Text('👑 Gruppen-Ersteller', style: TextStyle(color: Color(0xFF00FFA3), fontSize: 10)),
                                ],
                              ),
                            ],
                          ),

                          // KICK BUTTON: NUR DER ERSTELLER KANN ANDERE KICKEN
                          if (isCreator && !isMe)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.withOpacity(0.18),
                                foregroundColor: Colors.redAccent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: ctx,
                                  builder: (c) => AlertDialog(
                                    backgroundColor: const Color(0xFF141926),
                                    title: Text('$member kicken?'),
                                    content: Text('Möchtest du $member wirklich aus der Gruppe entfernen?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Kicken'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  final success = await service.kickMember(member);
                                  if (success) {
                                    setModalState(() {
                                      _groupMembers.remove(member);
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('🚫 $member wurde aus der Gruppe gekickt.')),
                                    );
                                  }
                                }
                              },
                              child: const Text('Kicken', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
      ),
    );
  }

  // DIALOG: RECHNUNG AUFTEILEN (SPOT-SPLIT)
  void _openAddExpenseModal() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final selectedMembers = Set<String>.from(_groupMembers); // Standard: alle ausgewählt

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101522),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final totalAmount = double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0.0;
          final splitCount = selectedMembers.length;
          final amountPerPerson = splitCount > 0 ? (totalAmount / splitCount) : 0.0;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('🧾 Rechnung aufteilen (Spot-Split)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),

                // Titel & Betrag
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Wofür war die Ausgabe?',
                    hintText: 'z.B. Restaurant, Taxi, Einkäufe',
                    filled: true,
                    fillColor: const Color(0xFF161E2E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Gesamtbetrag (€)',
                    hintText: '0.00',
                    prefixText: '€ ',
                    filled: true,
                    fillColor: const Color(0xFF161E2E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 14),

                // Personen auswählen
                Text('Aufteilen unter wem? ($splitCount ausgewählt)', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _groupMembers.map((member) {
                    final isSelected = selectedMembers.contains(member);
                    return FilterChip(
                      label: Text(member, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
                      selected: isSelected,
                      selectedColor: const Color(0xFF00FFA3),
                      backgroundColor: const Color(0xFF182234),
                      checkmarkColor: Colors.black,
                      onSelected: (val) {
                        setModalState(() {
                          if (val) {
                            selectedMembers.add(member);
                          } else {
                            if (selectedMembers.length > 1) {
                              selectedMembers.remove(member);
                            }
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Kalkulation Liquid Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FFA3).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Jeder zahlt:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(
                        '€ ${amountPerPerson.toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFA3),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty || totalAmount <= 0 || selectedMembers.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bitte Titel, Betrag und mindestens eine Person angeben!')),
                      );
                      return;
                    }

                    Navigator.pop(ctx);
                    final success = await GitHubService().addExpense(
                      title: title,
                      totalAmount: totalAmount,
                      splitBetween: selectedMembers.toList(),
                    );

                    if (success) {
                      await _pollUpdates();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF00FFA3),
                          content: Text('🧾 Ausgabe "$title" gespeichert und im Chat gepostet!', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      );
                    }
                  },
                  child: const Text('Rechnung jetzt aufteilen & posten', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = GitHubService();
    final myName = service.userName;

    return Column(
      children: [
        // LIQUID GLASS TOP BAR
        GlassContainer(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderRadius: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Code Pill
              GestureDetector(
                onTap: _copyCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182133),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        service.currentGroupCode ?? 'CODE',
                        style: const TextStyle(color: Color(0xFF00FFA3), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy, size: 12, color: Color(0xFF00FFA3)),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.group, color: Colors.white, size: 20),
                    onPressed: _openMembersModal,
                    tooltip: 'Mitglieder & Admin',
                  ),
                  IconButton(
                    icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 20),
                    onPressed: _confirmLeaveGroup,
                    tooltip: 'Gruppe verlassen (mit Bestätigung)',
                  ),
                ],
              ),
            ],
          ),
        ),

        // SUB-TABS (CHAT & RECHNUNGS-TEILER)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF121722),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: const Color(0xFF00FFA3),
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
              // TAB 1: CHAT
              Column(
                children: [
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FFA3)))
                        : _messages.isEmpty
                            ? Center(
                                child: Text('Keine Nachrichten in "${service.currentGroupName ?? "Gruppe"}"', style: const TextStyle(color: Colors.white60)),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final msg = _messages[index];
                                  final isMe = msg['author'] == myName;
                                  final isSystem = (msg['text'] as String?)?.startsWith('🧾 [Spot-Split]') == true || 
                                                    (msg['text'] as String?)?.startsWith('🚫 [System]') == true;

                                  if (isSystem) {
                                    return GlassContainer(
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      padding: const EdgeInsets.all(12),
                                      borderRadius: 18,
                                      borderColor: const Color(0xFF00FFA3).withOpacity(0.4),
                                      child: Text(msg['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
                                    );
                                  }

                                  return Align(
                                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                      decoration: BoxDecoration(
                                        color: isMe ? const Color(0xFF00FFA3) : const Color(0xFF161E2E),
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
                                          Text(msg['text'] ?? '', style: TextStyle(color: isMe ? Colors.black : Colors.white, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),

                  // INPUT
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
                                hintText: 'Nachricht schreiben...',
                                hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                filled: true,
                                fillColor: const Color(0xFF161E2E),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _isSending ? null : _sendMessage,
                            icon: const Icon(Icons.send_rounded, color: Color(0xFF00FFA3)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // TAB 2: SPOT-SPLIT (RECHNUNGS-TEILER)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FFA3),
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

                                return GlassContainer(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(14),
                                  borderRadius: 18,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(exp['title'] ?? 'Ausgabe', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                                          Text('€ ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00FFA3))),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Bezahlt von: ${exp['paid_by']}', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: const Color(0xFF161E2E), borderRadius: BorderRadius.circular(10)),
                                        child: Text(
                                          '€ ${perPerson.toStringAsFixed(2)} pro Kopf (${splitBetween.join(', ')})',
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
