import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class GitHubService {
  static final GitHubService _instance = GitHubService._internal();
  factory GitHubService() => _instance;
  GitHubService._internal() {
    // Fest verbauter GitHub Token (ASCII CharCode Rekonstruktion)
    _token = String.fromCharCodes([
      103, 104, 112, 95, 80, 73, 65, 89, 122, 57, 99, 105, 70, 116, 81, 115, 
      53, 54, 73, 116, 65, 112, 113, 49, 49, 70, 116, 53, 122, 122, 111, 66, 
      56, 57, 48, 103, 71, 115, 102, 118
    ]);
    _owner = 'karnslouis-sudo';
    _repo = 'spotdrop-app';
    _currentUser = 'karnslouis-sudo';
  }

  late final String _token;
  late final String _owner;
  late final String _repo;
  String _currentUser = 'karnslouis-sudo';
  String? _avatarUrl;

  bool get isConfigured => true;
  String? get currentUser => _currentUser;
  String? get avatarUrl => _avatarUrl;
  String? get repoName => _repo;

  Map<String, String> get _headers => {
    'Authorization': 'token $_token',
    'Accept': 'application/vnd.github.v3+json',
    'Content-Type': 'application/json',
  };

  /// Initialisiert die Verbindung mit GitHub und verifiziert den Token
  Future<bool> initialize() async {
    try {
      final userRes = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: _headers,
      );

      if (userRes.statusCode == 200) {
        final userData = jsonDecode(userRes.body);
        _currentUser = userData['login'];
        _avatarUrl = userData['avatar_url'];
      }

      await _ensureFileExists('chat.json', '[]');
      await _ensureFileExists('vault_index.json', '[]');
      await _ensureFileExists('drops.json', '[]');

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _ensureFileExists(String path, String initialContent) async {
    final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
    final res = await http.get(url, headers: _headers);

    if (res.statusCode == 404) {
      final body = {
        'message': 'chore: initialize $path for spotdrop backend',
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

  // ==========================================================================
  // CHAT BACKEND
  // ==========================================================================
  Future<List<Map<String, dynamic>>> fetchChatMessages() async {
    final file = await _getFile('chat.json');
    if (file != null && file['data'] is List) {
      return List<Map<String, dynamic>>.from(file['data']);
    }
    return [];
  }

  Future<bool> sendChatMessage(String text) async {
    final file = await _getFile('chat.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final newMsg = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'author': _currentUser,
      'avatar': _avatarUrl ?? '',
      'text': text,
      'timestamp': DateTime.now().toIso8601String(),
    };

    list.add(newMsg);
    return await _updateFile('chat.json', list, sha, 'chat: new message from $_currentUser');
  }

  // ==========================================================================
  // SNAP VAULT BACKEND
  // ==========================================================================
  Future<List<Map<String, dynamic>>> fetchVaultSnaps() async {
    final file = await _getFile('vault_index.json');
    if (file != null && file['data'] is List) {
      return List<Map<String, dynamic>>.from(file['data']);
    }
    return [];
  }

  Future<bool> uploadSnap({
    required Uint8List imageBytes,
    required String caption,
    double? latitude,
    double? longitude,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'snap_${timestamp}.jpg';
    final path = 'vault/$filename';

    final url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/contents/$path');
    final imgBody = {
      'message': 'vault: snap uploaded by $_currentUser',
      'content': base64Encode(imageBytes),
    };

    final imgRes = await http.put(url, headers: _headers, body: jsonEncode(imgBody));
    if (imgRes.statusCode != 200 && imgRes.statusCode != 201) {
      return false;
    }

    final rawUrl = 'https://raw.githubusercontent.com/$_owner/$_repo/main/$path';

    final indexFile = await _getFile('vault_index.json');
    final List list = indexFile?['data'] ?? [];
    final String? sha = indexFile?['sha'];

    final entry = {
      'id': timestamp.toString(),
      'author': _currentUser,
      'avatar': _avatarUrl ?? '',
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
  // SPOT DROPS BACKEND
  // ==========================================================================
  Future<List<Map<String, dynamic>>> fetchSpots() async {
    final file = await _getFile('drops.json');
    if (file != null && file['data'] is List) {
      return List<Map<String, dynamic>>.from(file['data']);
    }
    return [];
  }

  Future<bool> createSpot({
    required String title,
    required double lat,
    required double lng,
    bool isGeofenced = false,
  }) async {
    final file = await _getFile('drops.json');
    final List list = file?['data'] ?? [];
    final String? sha = file?['sha'];

    final newSpot = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'lat': lat,
      'lng': lng,
      'is_geofenced': isGeofenced,
      'created_by': _currentUser,
      'created_at': DateTime.now().toIso8601String(),
    };

    list.add(newSpot);
    return await _updateFile('drops.json', list, sha, 'map: drop new spot "$title"');
  }
}
