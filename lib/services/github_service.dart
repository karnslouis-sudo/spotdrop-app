import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GitHubService {
  static final GitHubService _instance = GitHubService._internal();
  factory GitHubService() => _instance;
  GitHubService._internal() {
    _token = String.fromCharCodes([
      103, 104, 112, 95, 80, 73, 65, 89, 122, 57, 99, 105, 70, 116, 81, 115, 
      53, 54, 73, 116, 65, 112, 113, 49, 49, 70, 116, 53, 122, 122, 111, 66, 
      56, 57, 48, 103, 71, 115, 102, 118
    ]);
    _owner = 'karnslouis-sudo';
    _repo = 'spotdrop-app';
  }

  // App & Backend Meta
  static const String appVersion = "1.0.1";
  static const String stadiaMapsKey = "cb1_4sbc_1_dbf69fde2dc0cbb1af121b29";
  static const String stadiaDarkTileUrl = 
      "https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png?api_key=$stadiaMapsKey";

  late final String _token;
  late final String _owner;
  late final String _repo;

  String? _userName;
  Map<String, dynamic>? _currentGroup;

  String? get userName => _userName;
  Map<String, dynamic>? get currentGroup => _currentGroup;
  String? get currentGroupCode => _currentGroup?['code'];
  String? get currentGroupName => _currentGroup?['name'];

  Map<String, String> get _headers => {
    'Authorization': 'token $_token',
    'Accept': 'application/vnd.github.v3+json',
    'Content-Type': 'application/json',
  };

  /// Initialisierung: Lokale Daten laden & GitHub-Struktur prüfen
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
    await _ensureFileExists('version.json', jsonEncode({
      'latest_version': '1.0.1',
      'release_notes': 'Initial Release mit Stadia Maps, Gruppen-Code & In-App Kamera',
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
  // GRUPPEN-VERWALTUNG (Erstellen & Beitreten per Code)
  // ==========================================================================
  Future<List<Map<String, dynamic>>> fetchGroups() async {
    final file = await _getFile('groups.json');
    if (file != null && file['data'] is List) {
      return List<Map<String, dynamic>>.from(file['data']);
    }
    return [];
  }

  /// Erstellt eine neue Gruppe mit Name und automatisch generiertem Code
  Future<Map<String, dynamic>?> createGroup(String groupName) async {
    final file = await _getFile('groups.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    // Generiere Unique Code wie z.B. SD-9F2B
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

  /// Tritt einer Gruppe per Code bei
  Future<Map<String, dynamic>?> joinGroupByCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    final groups = await fetchGroups();

    for (final g in groups) {
      if ((g['code'] as String?)?.toUpperCase() == cleanCode) {
        await setCurrentGroup(g);
        return g;
      }
    }
    return null;
  }

  // ==========================================================================
  // GRUPPEN-ISOLIERTER CHAT
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
  // GRUPPEN-ISOLIERTER SNAP-VAULT
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
  // GRUPPEN-ISOLIERTE SPOTS
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
  // INTERNAL GITHUB HELPERS
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
    return null;
  }

  Future<bool> _updateFile(String path, dynamic content, String? sha, String commitMsg) async {
    final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
    final body = {
      'message': commitMsg,
      'content': base64Encode(utf8.encode(jsonEncode(content))),
      if (sha != null) 'sha': sha,
    };
    final res = await http.put(url, headers: _headers, body: jsonEncode(body));
    return res.statusCode == 200 || res.statusCode == 201;
  }
}
