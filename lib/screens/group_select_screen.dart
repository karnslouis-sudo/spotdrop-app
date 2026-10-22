import 'package:flutter/material.dart';
import '../services/github_service.dart';

class GroupSelectScreen extends StatefulWidget {
  final VoidCallback onGroupReady;
  const GroupSelectScreen({super.key, required this.onGroupReady});

  @override
  State<GroupSelectScreen> createState() => _GroupSelectScreenState();
}

class _GroupSelectScreenState extends State<GroupSelectScreen> {
  final _nameController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _groupCodeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  int _activeTab = 0; // 0 = Beitreten mit Code, 1 = Neue Gruppe erstellen

  @override
  void initState() {
    super.initState();
    final existingName = GitHubService().userName;
    if (existingName != null) {
      _nameController.text = existingName;
    }
  }

  Future<void> _handleJoinOrCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Bitte gib deinen Namen an!');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await GitHubService().setUserName(name);

    if (_activeTab == 0) {
      // Mit Code beitreten
      final code = _groupCodeController.text.trim();
      if (code.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Bitte gib den Gruppen-Code ein (z. B. SD-89F2).';
        });
        return;
      }

      final group = await GitHubService().joinGroupByCode(code);
      setState(() => _isLoading = false);

      if (group != null) {
        widget.onGroupReady();
      } else {
        setState(() => _errorMessage = 'Keine Gruppe mit Code "$code" gefunden.');
      }
    } else {
      // Neue Gruppe erstellen
      final groupName = _groupNameController.text.trim();
      if (groupName.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Bitte gib einen Gruppennamen ein!';
        });
        return;
      }

      final group = await GitHubService().createGroup(groupName);
      setState(() => _isLoading = false);

      if (group != null) {
        widget.onGroupReady();
      } else {
        setState(() => _errorMessage = 'Fehler beim Erstellen der Gruppe.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF00FFA3)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFA3).withOpacity(0.3),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('SD', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 24)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Willkommen bei Spotdrop',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Private Gruppen, gemeinsamer Fotospeicher & Live-Map.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
                const SizedBox(height: 28),

                // 1. Dein Name (Pflichtangabe)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121722),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF1E283C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '1. DEIN NAME / SPITZNAME *',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00FFA3), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: 'Wie soll dich deine Crew sehen?',
                          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          prefixIcon: const Icon(Icons.person, color: Color(0xFF00FFA3), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF182133),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 2. Gruppe wählen (Tab: Join oder Create)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121722),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF1E283C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '2. CREW-GRUPPE *',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6366F1), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 12),

                      // Segmented Tab
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _activeTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _activeTab == 0 ? const Color(0xFF00FFA3) : const Color(0xFF182133),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    'Code eingeben',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: _activeTab == 0 ? Colors.black : Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _activeTab = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _activeTab == 1 ? const Color(0xFF00FFA3) : const Color(0xFF182133),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    '+ Neue Gruppe',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: _activeTab == 1 ? Colors.black : Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (_activeTab == 0) ...[
                        // Code Eingabe
                        TextField(
                          controller: _groupCodeController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 2),
                          decoration: InputDecoration(
                            hintText: 'SD-XXXX',
                            hintStyle: TextStyle(color: Colors.grey.shade600, letterSpacing: 1),
                            prefixIcon: const Icon(Icons.vpn_key, color: Color(0xFF00FFA3), size: 20),
                            filled: true,
                            fillColor: const Color(0xFF182133),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Frage ein Crew-Mitglied nach dem Beitritts-Code.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ] else ...[
                        // Gruppen-Name Eingabe
                        TextField(
                          controller: _groupNameController,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: 'z.B. Berlin Weekend, Roadtrip 2026',
                            hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            prefixIcon: const Icon(Icons.group_add, color: Color(0xFF6366F1), size: 20),
                            filled: true,
                            fillColor: const Color(0xFF182133),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Erzeugt automatisch einen neuen Code, den du teilen kannst.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),

                // Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleJoinOrCreate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFA3),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(
                          _activeTab == 0 ? 'Gruppe beitreten' : 'Gruppe jetzt erstellen',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
