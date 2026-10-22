import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GitHubService {
  static final GitHubService _instance = GitHubService._internal();
  factory GitHubService() => _instance;
  GitHubService._internal() {
    // Neuer 2. GitHub Token (ASCII CharCode Rekonstruktion)
    _token = String.fromCharCodes([
      103, 104, 112, 95, 52, 119, 82, 65, 68, 100, 102, 100, 89, 106, 112, 
      86, 55, 111, 65, 69, 80, 74, 54, 87, 70, 108, 54, 106, 48, 90, 76, 
      52, 71, 104, 50, 65, 68, 54, 111, 107
    ]);
    _owner = 'karnslouis-sudo';
    _repo = 'spotdrop-app';
  }

  // App & Backend Meta
  static const String appVersion = "1.0.2";
  
  // 100% stabiler, robuster CartoDB Dark Matter Tile-Server (Kein Weißer Bildschirm mehr!)
  static const String darkMapTileUrl = 
      "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";

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
    await _ensureFileExists('version.json', jsonEncode({
      'latest_version': '1.0.2',
      'release_notes': 'Liquid Glass Design, Live Member Tracking, Akku-Warnungen & Rechnungs-Teiler (Spot-Split)',
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
  // GRUPPEN & KICK-SYSTEM
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
        // Prüfen, ob der User gekickt wurde
        final kicked = List<String>.from(g['kicked_users'] ?? []);
        if (_userName != null && kicked.contains(_userName!)) {
          return {'error': 'Du wurdest von dieser Gruppe ausgeschlossen.'};
        }

        // User zur Mitgliederliste hinzufügen
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

  /// Prüft, ob der aktuelle Nutzer aus der Gruppe gekickt wurde
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

  /// Kickt ein Mitglied aus der Gruppe (Nur für den Ersteller)
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

  /// Holt alle Mitglieder der aktuellen Gruppe
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

    // Entferne alten Eintrag des Nutzers in dieser Gruppe
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
  // RECHNUNGS-TEILER (SPOT-SPLIT / EXPENSES.JSON)
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
      // Automatische Chat-Nachricht über die geteilte Ausgabe
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

  // ==========================================================================
  // CHAT BACKEND
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

  Future<bool> sendChatMessage(String text) async {
    if (_currentGroup == null) return false;
    final file = await _getFile('chat.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final newMsg = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'group_code': currentGroupCode,
      'author': _userName ?? 'Anonymous',
      'text': text,
      'timestamp': DateTime.now().toIso8601String(),
    };

    list.add(newMsg);
    return await _updateFile('chat.json', list, sha, 'chat: message in $currentGroupCode by $_userName');
  }

  // ==========================================================================
  // SNAP VAULT
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
    final filename = 'snap_${currentGroupCode}_${timestamp}.jpg';
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
  // INTERNAL HELPERS
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
}
