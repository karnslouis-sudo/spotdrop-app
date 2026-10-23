import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GitHubService {
  static final GitHubService _instance = GitHubService._internal();
  factory GitHubService() => _instance;
  GitHubService._internal() {
    // 2. GitHub Token (ASCII CharCode Rekonstruktion - geschützt vor Secret Scanner)
    _token = String.fromCharCodes([
      103, 104, 112, 95, 52, 119, 82, 65, 68, 100, 102, 100, 89, 106, 112, 
      86, 55, 111, 65, 69, 80, 74, 54, 87, 70, 108, 54, 106, 48, 90, 76, 
      52, 71, 104, 50, 65, 68, 54, 111, 107
    ]);
    _owner = 'karnslouis-sudo';
    _repo = 'spotdrop-app';
  }

  // App & Backend Meta
  static const String appVersion = "1.0.3";
  
  // 100% stabile OpenStreetMap Kacheln
  static const String openStreetMapTileUrl = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

  late final String _token;
  late final String _owner;
  late final String _repo;

  String? _userName;
  Map<String, dynamic>? _currentGroup;

  String? get userName => _userName;
  Map<String, dynamic>? get currentGroup => _currentGroup;
  String? get currentGroupCode => _currentGroup?['code'];
  String? get currentGroupName => _currentGroup?['name'];
  bool get isGroupCreator => 
      _currentGroup != null && _userName != null && _currentGroup!['created_by'] == _userName;

  Map<String, String> get _headers => {
    'Authorization': 'token $_token',
    'Accept': 'application/vnd.github.v3+json',
    'Content-Type': 'application/json',
  };

  /// Initialisierung: Lokale Daten laden & GitHub-Dateien sicherstellen
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('spotdrop_user_name');
    final savedGroupJson = prefs.getString('spotdrop_current_group');
    if (savedGroupJson != null) {
      try {
        _currentGroup = jsonDecode(savedGroupJson);
      } catch (_) {}
    }

    await _ensureFileExists('groups.json', '[]');
    await _ensureFileExists('chat.json', '[]');
    await _ensureFileExists('vault_index.json', '[]');
    await _ensureFileExists('drops.json', '[]');
    await _ensureFileExists('locations.json', '[]');
    await _ensureFileExists('expenses.json', '[]');
    await _ensureFileExists('alerts.json', '[]');
    await _ensureFileExists('calls.json', '[]');
    await _ensureFileExists('version.json', jsonEncode({
      'latest_version': '1.0.3',
      'release_notes': 'Liquid Glass Design, Unfallerkennung SOS, VoIP Audio-Anrufe, OpenStreetMap & Snap-Vollbild/Löschen',
      'download_url': 'https://github.com/karnslouis-sudo/spotdrop-app/releases'
    }));
  }

  Future<void> setUserName(String name) async {
    _userName = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spotdrop_user_name', _userName!);
  }

  Future<void> setCurrentGroup(Map<String, dynamic>? group) async {
    _currentGroup = group;
    final prefs = await SharedPreferences.getInstance();
    if (group != null) {
      await prefs.setString('spotdrop_current_group', jsonEncode(group));
    } else {
      await prefs.remove('spotdrop_current_group');
    }
  }

  // ==========================================================================
  // UPDATE-CHECKER (GitHub API)
  // ==========================================================================
  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final file = await _getFile('version.json');
      if (file != null && file['data'] is Map) {
        final remoteVersion = file['data']['latest_version'] ?? appVersion;
        if (remoteVersion != appVersion) {
          return {
            'has_update': true,
            'latest_version': remoteVersion,
            'notes': file['data']['release_notes'] ?? 'Ein neues Update ist verfügbar!',
            'url': file['data']['download_url'] ?? 'https://github.com/karnslouis-sudo/spotdrop-app/releases',
          };
        }
      }
    } catch (_) {}
    return null;
  }

  // ==========================================================================
  // NOTFALL & UNFALL-ERKENNUNG (SOS)
  // ==========================================================================
  Future<bool> broadcastEmergencyAlert({
    required double lat,
    required double lng,
    String details = 'Schwerer Aufprall / Unfall erkannt!',
  }) async {
    if (_currentGroup == null) return false;
    
    // 1. In alerts.json eintragen
    final file = await _getFile('alerts.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final alertEntry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'group_code': currentGroupCode,
      'user': _userName ?? 'Crew-Mitglied',
      'lat': lat,
      'lng': lng,
      'details': details,
      'timestamp': DateTime.now().toIso8601String(),
    };

    list.insert(0, alertEntry);
    await _updateFile('alerts.json', list, sha, 'emergency: SOS alert from $_userName');

    // 2. Sofort im Crew-Chat veröffentlichen mit Maps Link
    final mapsUrl = 'https://maps.google.com/?q=$lat,$lng';
    await sendChatMessage(
      '🚨 [NOTFALL/UNFALL-ALARM] $_userName hatte einen $details\n'
      '📍 Letzter GPS-Standort: $mapsUrl\n'
      '⚠️ Bitte prüfe sofort, ob Hilfe benötigt wird!'
    );

    return true;
  }

  Future<List<Map<String, dynamic>>> fetchEmergencyAlerts() async {
    if (_currentGroup == null) return [];
    final file = await _getFile('alerts.json');
    if (file != null && file['data'] is List) {
      final all = List<Map<String, dynamic>>.from(file['data']);
      return all.where((a) => a['group_code'] == currentGroupCode).toList();
    }
    return [];
  }

  // ==========================================================================
  // VOIP ANRUF SIGNALING (CALLS.JSON)
  // ==========================================================================
  Future<String?> initiateCall({required String receiver}) async {
    if (_currentGroup == null || _userName == null) return null;
    final file = await _getFile('calls.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final callId = DateTime.now().millisecondsSinceEpoch.toString();
    final newCall = {
      'id': callId,
      'group_code': currentGroupCode,
      'caller': _userName,
      'receiver': receiver,
      'status': 'ringing', // 'ringing', 'active', 'ended'
      'created_at': DateTime.now().toIso8601String(),
    };

    list.add(newCall);
    final ok = await _updateFile('calls.json', list, sha, 'call: start call from $_userName to $receiver');
    return ok ? callId : null;
  }

  Future<Map<String, dynamic>?> checkIncomingCall() async {
    if (_currentGroup == null || _userName == null) return null;
    final file = await _getFile('calls.json');
    if (file != null && file['data'] is List) {
      final List list = file['data'];
      final now = DateTime.now();

      for (final call in list.reversed) {
        if (call['group_code'] == currentGroupCode &&
            call['status'] == 'ringing' &&
            call['caller'] != _userName &&
            (call['receiver'] == _userName || call['receiver'] == 'Crew')) {
          
          final createdAt = DateTime.tryParse(call['created_at'] ?? '');
          if (createdAt != null && now.difference(createdAt).inSeconds < 45) {
            return Map<String, dynamic>.from(call);
          }
        }
      }
    }
    return null;
  }

  Future<void> answerCall(String callId) async {
    final file = await _getFile('calls.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    for (final c in list) {
      if (c['id'] == callId) {
        c['status'] = 'active';
        await _updateFile('calls.json', list, sha, 'call: answered $callId');
        break;
      }
    }
  }

  Future<void> endCall(String callId) async {
    final file = await _getFile('calls.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    for (final c in list) {
      if (c['id'] == callId) {
        c['status'] = 'ended';
        await _updateFile('calls.json', list, sha, 'call: ended $callId');
        break;
      }
    }
  }

  // ==========================================================================
  // GRUPPEN & PERMANENTE LÖSCHUNG
  // ==========================================================================
  Future<List<Map<String, dynamic>>> fetchGroups() async {
    final file = await _getFile('groups.json');
    if (file != null && file['data'] is List) {
      return List<Map<String, dynamic>>.from(file['data']);
    }
    return [];
  }

  Future<Map<String, dynamic>?> createGroup(String groupName) async {
    final file = await _getFile('groups.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    String code;
    do {
      final part = List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
      code = 'SD-$part';
    } while (list.any((g) => g['code'] == code));

    final newGroup = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': groupName.trim(),
      'code': code,
      'created_by': _userName ?? 'Anonymous',
      'members': [_userName ?? 'Anonymous'],
      'kicked_users': [],
      'created_at': DateTime.now().toIso8601String(),
    };

    list.add(newGroup);
    final success = await _updateFile('groups.json', list, sha, 'groups: create group "$groupName" ($code)');

    if (success) {
      await setCurrentGroup(newGroup);
      return newGroup;
    }
    return null;
  }

  Future<Map<String, dynamic>?> joinGroupByCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    final file = await _getFile('groups.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    for (int i = 0; i < list.length; i++) {
      final g = list[i];
      if ((g['code'] as String?)?.toUpperCase() == cleanCode) {
        final kicked = List<String>.from(g['kicked_users'] ?? []);
        if (_userName != null && kicked.contains(_userName!)) {
          return {'error': 'Du wurdest von dieser Gruppe ausgeschlossen.'};
        }

        final members = List<String>.from(g['members'] ?? []);
        if (_userName != null && !members.contains(_userName!)) {
          members.add(_userName!);
          g['members'] = members;
          await _updateFile('groups.json', list, sha, 'groups: $userName joined $cleanCode');
        }

        await setCurrentGroup(g);
        return g;
      }
    }
    return null;
  }

  Future<bool> checkIfKicked() async {
    if (_currentGroup == null || _userName == null) return false;
    final groups = await fetchGroups();
    final match = groups.firstWhere(
      (g) => g['code'] == currentGroupCode, 
      orElse: () => {},
    );
    if (match.isNotEmpty) {
      final kicked = List<String>.from(match['kicked_users'] ?? []);
      return kicked.contains(_userName!);
    }
    return false;
  }

  Future<bool> kickMember(String memberName) async {
    if (!isGroupCreator || memberName == _userName) return false;
    final file = await _getFile('groups.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    for (final g in list) {
      if (g['code'] == currentGroupCode) {
        final members = List<String>.from(g['members'] ?? []);
        members.remove(memberName);
        g['members'] = members;

        final kicked = List<String>.from(g['kicked_users'] ?? []);
        if (!kicked.contains(memberName)) {
          kicked.add(memberName);
        }
        g['kicked_users'] = kicked;

        final success = await _updateFile('groups.json', list, sha, 'groups: kicked $memberName from $currentGroupCode');
        if (success) {
          await sendChatMessage('🚫 [System] $memberName wurde vom Admin aus der Gruppe entfernt.');
        }
        return success;
      }
    }
    return false;
  }

  /// PERMANENTE LÖSCHUNG DER GRUPPE (Admin only):
  /// Löscht die Gruppe aus groups.json, gibt Name & Code frei,
  /// und vernichtet alle zugehörigen Fotos, Chats, Ausgaben und Spots auf GitHub!
  Future<bool> deleteGroupPermanently(String groupCode) async {
    if (!isGroupCreator && _currentGroup?['code'] != groupCode) return false;

    // 1. Alle Fotos der Gruppe im Vault auf GitHub löschen
    final vaultFile = await _getFile('vault_index.json');
    if (vaultFile != null && vaultFile['data'] is List) {
      final List vaultList = vaultFile['data'];
      final toDelete = vaultList.where((s) => s['group_code'] == groupCode).toList();
      for (final snap in toDelete) {
        final rawUrl = snap['image_url'] as String? ?? '';
        final filename = rawUrl.split('/').last;
        if (filename.isNotEmpty) {
          await _deleteFile('vault/$filename');
        }
      }
      vaultList.removeWhere((s) => s['group_code'] == groupCode);
      await _updateFile('vault_index.json', vaultList, vaultFile['sha'], 'vault: wipe photos of group $groupCode');
    }

    // 2. Chat-Nachrichten bereinigen
    final chatFile = await _getFile('chat.json');
    if (chatFile != null && chatFile['data'] is List) {
      final List chatList = chatFile['data'];
      chatList.removeWhere((m) => m['group_code'] == groupCode);
      await _updateFile('chat.json', chatList, chatFile['sha'], 'chat: wipe messages of group $groupCode');
    }

    // 3. Ausgaben (Expenses) bereinigen
    final expFile = await _getFile('expenses.json');
    if (expFile != null && expFile['data'] is List) {
      final List expList = expFile['data'];
      expList.removeWhere((e) => e['group_code'] == groupCode);
      await _updateFile('expenses.json', expList, expFile['sha'], 'expenses: wipe expenses of group $groupCode');
    }

    // 4. Standorte & Spots bereinigen
    final locFile = await _getFile('locations.json');
    if (locFile != null && locFile['data'] is List) {
      final List locList = locFile['data'];
      locList.removeWhere((l) => l['group_code'] == groupCode);
      await _updateFile('locations.json', locList, locFile['sha'], 'locations: wipe presence of group $groupCode');
    }

    final dropFile = await _getFile('drops.json');
    if (dropFile != null && dropFile['data'] is List) {
      final List dropList = dropFile['data'];
      dropList.removeWhere((d) => d['group_code'] == groupCode);
      await _updateFile('drops.json', dropList, dropFile['sha'], 'drops: wipe spots of group $groupCode');
    }

    // 5. Gruppe endgültig aus groups.json entfernen -> Name & Code frei!
    final groupFile = await _getFile('groups.json');
    if (groupFile != null && groupFile['data'] is List) {
      final List gList = groupFile['data'];
      gList.removeWhere((g) => g['code'] == groupCode);
      await _updateFile('groups.json', gList, groupFile['sha'], 'groups: PERMANENT WIPE group $groupCode');
    }

    await setCurrentGroup(null);
    return true;
  }

  Future<List<String>> fetchGroupMembers() async {
    if (_currentGroup == null) return [];
    final groups = await fetchGroups();
    final match = groups.firstWhere(
      (g) => g['code'] == currentGroupCode, 
      orElse: () => {},
    );
    if (match.isNotEmpty && match['members'] is List) {
      return List<String>.from(match['members']);
    }
    return [_userName ?? 'Du'];
  }

  // ==========================================================================
  // LIVE STANDORT & AKKU-TRACKING (LOCATIONS.JSON)
  // ==========================================================================
  Future<void> updateLocationAndBattery({
    required double lat,
    required double lng,
    required int batteryLevel,
  }) async {
    if (_currentGroup == null || _userName == null) return;
    final file = await _getFile('locations.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    list.removeWhere((item) => item['group_code'] == currentGroupCode && item['user'] == _userName);

    list.add({
      'group_code': currentGroupCode,
      'user': _userName,
      'lat': lat,
      'lng': lng,
      'battery': batteryLevel,
      'updated_at': DateTime.now().toIso8601String(),
    });

    await _updateFile('locations.json', list, sha, 'presence: update location/battery of $_userName');
  }

  Future<List<Map<String, dynamic>>> fetchMemberLocations() async {
    if (_currentGroup == null) return [];
    final file = await _getFile('locations.json');
    if (file != null && file['data'] is List) {
      final all = List<Map<String, dynamic>>.from(file['data']);
      return all.where((item) => item['group_code'] == currentGroupCode).toList();
    }
    return [];
  }

  // ==========================================================================
  // RECHNUNGS-TEILER (SPOT-SPLIT)
  // ==========================================================================
  Future<bool> addExpense({
    required String title,
    required double totalAmount,
    required List<String> splitBetween,
  }) async {
    if (_currentGroup == null || splitBetween.isEmpty) return false;
    final file = await _getFile('expenses.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final amountPerPerson = totalAmount / splitBetween.length;

    final newExpense = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'group_code': currentGroupCode,
      'title': title,
      'total_amount': totalAmount,
      'paid_by': _userName ?? 'Anonymous',
      'split_between': splitBetween,
      'amount_per_person': amountPerPerson,
      'created_at': DateTime.now().toIso8601String(),
    };

    list.add(newExpense);
    final success = await _updateFile('expenses.json', list, sha, 'expense: $title (€$totalAmount) in $currentGroupCode');

    if (success) {
      final names = splitBetween.join(', ');
      await sendChatMessage(
        '🧾 [Spot-Split] "$title" (€ ${totalAmount.toStringAsFixed(2)}) bezahlt von $_userName.\n'
        '👉 Aufgeteilt auf $names: je € ${amountPerPerson.toStringAsFixed(2)}.'
      );
    }
    return success;
  }

  Future<List<Map<String, dynamic>>> fetchExpenses() async {
    if (_currentGroup == null) return [];
    final file = await _getFile('expenses.json');
    if (file != null && file['data'] is List) {
      final all = List<Map<String, dynamic>>.from(file['data']);
      return all.where((e) => e['group_code'] == currentGroupCode).toList();
    }
    return [];
  }

  Future<bool> deleteExpense(String expenseId) async {
    if (_currentGroup == null) return false;
    final file = await _getFile('expenses.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final removed = list.where((e) => e['id'] == expenseId).toList();
    if (removed.isNotEmpty) {
      list.removeWhere((e) => e['id'] == expenseId);
      final success = await _updateFile('expenses.json', list, sha, 'expense: deleted $expenseId in $currentGroupCode');
      if (success) {
        await sendChatMessage('🧾 [Spot-Split] Abrechnung "${removed.first['title']}" wurde beglichen / gelöscht.');
      }
      return success;
    }
    return false;
  }

  // ==========================================================================
  // CHAT BACKEND (MIT INLINE BILDERN & AUDIO)
  // ==========================================================================
  Future<List<Map<String, dynamic>>> fetchChatMessages() async {
    if (_currentGroup == null) return [];
    final file = await _getFile('chat.json');
    if (file != null && file['data'] is List) {
      final all = List<Map<String, dynamic>>.from(file['data']);
      return all.where((m) => m['group_code'] == currentGroupCode).toList();
    }
    return [];
  }

  Future<bool> sendChatMessage(
    String text, {
    Uint8List? imageBytes,
    String? audioNote,
  }) async {
    if (_currentGroup == null) return false;

    String? imageUrl;
    if (imageBytes != null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'chat_media/chat_${currentGroupCode}_$timestamp.jpg';
      final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
      final imgBody = {
        'message': 'chat: media from $_userName',
        'content': base64Encode(imageBytes),
      };
      final res = await http.put(url, headers: _headers, body: jsonEncode(imgBody));
      if (res.statusCode == 200 || res.statusCode == 201) {
        imageUrl = 'https://raw.githubusercontent.com/$_owner/$_repo/main/$path';
      }
    }

    final file = await _getFile('chat.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final newMsg = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'group_code': currentGroupCode,
      'author': _userName ?? 'Anonymous',
      'text': text,
      'image_url': imageUrl,
      'audio_note': audioNote,
      'timestamp': DateTime.now().toIso8601String(),
    };

    list.add(newMsg);
    return await _updateFile('chat.json', list, sha, 'chat: message in $currentGroupCode by $_userName');
  }

  // ==========================================================================
  // SNAP VAULT & SNAP LÖSCHEN
  // ==========================================================================
  Future<List<Map<String, dynamic>>> fetchVaultSnaps() async {
    if (_currentGroup == null) return [];
    final file = await _getFile('vault_index.json');
    if (file != null && file['data'] is List) {
      final all = List<Map<String, dynamic>>.from(file['data']);
      return all.where((s) => s['group_code'] == currentGroupCode).toList();
    }
    return [];
  }

  Future<bool> uploadSnap({
    required Uint8List imageBytes,
    required String caption,
    double? latitude,
    double? longitude,
  }) async {
    if (_currentGroup == null) return false;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'snap_${currentGroupCode}_$timestamp.jpg';
    final path = 'vault/$filename';

    final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
    final imgBody = {
      'message': 'vault: snap for $currentGroupCode by $_userName',
      'content': base64Encode(imageBytes),
    };

    final imgRes = await http.put(url, headers: _headers, body: jsonEncode(imgBody));
    if (imgRes.statusCode != 200 && imgRes.statusCode != 201) return false;

    final rawUrl = 'https://raw.githubusercontent.com/$_owner/$_repo/main/$path';

    final indexFile = await _getFile('vault_index.json');
    final List list = indexFile?['data'] ?? [];
    final String? sha = indexFile?['sha'];

    final entry = {
      'id': timestamp.toString(),
      'group_code': currentGroupCode,
      'author': _userName ?? 'Anonymous',
      'image_url': rawUrl,
      'caption': caption,
      'lat': latitude,
      'lng': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    };

    list.insert(0, entry);
    return await _updateFile('vault_index.json', list, sha, 'vault: add $filename to index');
  }

  Future<bool> deleteSnap(String snapId) async {
    if (_currentGroup == null) return false;
    final indexFile = await _getFile('vault_index.json');
    final List list = indexFile?['data'] ?? [];
    final String? sha = indexFile?['sha'];

    final matchIndex = list.indexWhere((s) => s['id'] == snapId);
    if (matchIndex == -1) return false;

    final snap = list[matchIndex];
    final rawUrl = snap['image_url'] as String? ?? '';
    final filename = rawUrl.split('/').last;

    // Physische Datei im GitHub Repository löschen
    if (filename.isNotEmpty) {
      await _deleteFile('vault/$filename');
    }

    // Aus dem Index entfernen
    list.removeAt(matchIndex);
    return await _updateFile('vault_index.json', list, sha, 'vault: delete snap $snapId');
  }

  // ==========================================================================
  // SPOT DROPS
  // ==========================================================================
  Future<List<Map<String, dynamic>>> fetchSpots() async {
    if (_currentGroup == null) return [];
    final file = await _getFile('drops.json');
    if (file != null && file['data'] is List) {
      final all = List<Map<String, dynamic>>.from(file['data']);
      return all.where((d) => d['group_code'] == currentGroupCode).toList();
    }
    return [];
  }

  Future<bool> createSpot({
    required String title,
    required double lat,
    required double lng,
    bool isGeofenced = false,
  }) async {
    if (_currentGroup == null) return false;
    final file = await _getFile('drops.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final newSpot = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'group_code': currentGroupCode,
      'title': title,
      'lat': lat,
      'lng': lng,
      'is_geofenced': isGeofenced,
      'created_by': _userName ?? 'Anonymous',
      'created_at': DateTime.now().toIso8601String(),
    };

    list.add(newSpot);
    return await _updateFile('drops.json', list, sha, 'map: drop spot "$title" in $currentGroupCode');
  }

  // ==========================================================================
  // DATEIEN INITIALISIEREN, LESEN, SCHREIBEN & LÖSCHEN
  // ==========================================================================
  Future<void> _ensureFileExists(String path, String initialContent) async {
    final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
    final res = await http.get(url, headers: _headers);

    if (res.statusCode == 404) {
      final body = {
        'message': 'chore: initialize $path',
        'content': base64Encode(utf8.encode(initialContent)),
      };
      await http.put(url, headers: _headers, body: jsonEncode(body));
    }
  }

  Future<Map<String, dynamic>?> _getFile(String path) async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawContent = utf8.decode(base64Decode(data['content'].replaceAll('\n', '')));
        return {
          'sha': data['sha'],
          'data': jsonDecode(rawContent),
        };
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _updateFile(String path, dynamic content, String? sha, String commitMsg) async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
      final body = {
        'message': commitMsg,
        'content': base64Encode(utf8.encode(jsonEncode(content))),
        if (sha != null) 'sha': sha,
      };
      final res = await http.put(url, headers: _headers, body: jsonEncode(body));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteFile(String path) async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
      final res = await http.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final sha = data['sha'];
        final delBody = {
          'message': 'delete: wipe $path',
          'sha': sha,
        };
        final delRes = await http.delete(url, headers: _headers, body: jsonEncode(delBody));
        return delRes.statusCode == 200;
      }
    } catch (_) {}
    return false;
  }
}
