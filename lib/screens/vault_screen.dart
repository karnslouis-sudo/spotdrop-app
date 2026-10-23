import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/github_service.dart';
import '../services/theme_service.dart';
import '../widgets/glass_container.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _snaps = [];
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _fetchSnaps();
  }

  Future<void> _fetchSnaps() async {
    setState(() => _isLoading = true);
    final snaps = await GitHubService().fetchVaultSnaps();
    if (mounted) {
      setState(() {
        _snaps = snaps;
        _isLoading = false;
      });
    }
  }

  Future<void> _takeAndUploadSnap(ImageSource source) async {
    final accent = ThemeService().accentColor;
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1280,
      );

      if (file == null) return;

      setState(() => _isUploading = true);

      final Uint8List bytes = await file.readAsBytes();
      final success = await GitHubService().uploadSnap(
        imageBytes: bytes,
        caption: 'Snap vom ${DateTime.now().hour}:${DateTime.now().minute} Uhr',
      );

      if (mounted) {
        setState(() => _isUploading = false);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: accent,
              content: const Text('📸 Snap erfolgreich in GitHub Vault gespeichert!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          );
          await _fetchSnaps();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload auf GitHub Server fehlgeschlagen.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  void _openFullScreenSnap(Map<String, dynamic> snap) {
    final url = snap['image_url'] ?? '';
    final author = snap['author'] ?? 'Anonymous';
    final caption = snap['caption'] ?? '';
    final timestamp = snap['timestamp'] ?? '';
    final id = snap['id']?.toString() ?? '';
    final accent = ThemeService().accentColor;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black.withOpacity(0.6),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caption.isNotEmpty ? caption : 'Snap', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                Text('Von $author • $timestamp', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Snap löschen',
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (dCtx) => AlertDialog(
                      backgroundColor: const Color(0xFF141926),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent)),
                      title: const Row(
                        children: [
                          Icon(Icons.delete_forever, color: Colors.redAccent),
                          SizedBox(width: 8),
                          Text('Snap löschen?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      content: const Text(
                        'Möchtest du dieses Foto wirklich endgültig aus dem GitHub Tresor löschen?',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx),
                          child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                          onPressed: () async {
                            Navigator.pop(dCtx);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lösche Foto vom Server...')),
                            );
                            await GitHubService().deleteSnap(id);
                            await _fetchSnaps();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(backgroundColor: Colors.redAccent, content: Text('🗑️ Snap wurde dauerhaft gelöscht.')),
                              );
                            }
                          },
                          child: const Text('Endgültig löschen'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.8,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) => Center(
                  child: CircularProgressIndicator(color: accent),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 60, color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService().accentColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1420),
        title: const Text('Snap-Vault (Foto-Tresor)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            onPressed: _fetchSnaps,
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? Center(child: CircularProgressIndicator(color: accent))
              : _snaps.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library_outlined, size: 60, color: Colors.grey.shade700),
                          const SizedBox(height: 16),
                          const Text(
                            'Der Snap-Vault ist noch leer',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Snappe ein Foto – es wird sofort in dein\nGitHub Repository übertragen!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _isUploading ? null : () => _takeAndUploadSnap(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Ersten Snap machen'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _snaps.length,
                      itemBuilder: (context, index) {
                        final snap = _snaps[index];
                        final url = snap['image_url'] ?? '';

                        return GestureDetector(
                          onTap: () => _openFullScreenSnap(snap),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: const Color(0xFF161E2E),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF161E2E),
                                child: const Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

          if (_isUploading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: accent),
                    const SizedBox(height: 16),
                    const Text(
                      'Lade Snap auf GitHub Server hoch...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton.extended(
          onPressed: _isUploading ? null : () => _takeAndUploadSnap(ImageSource.camera),
          backgroundColor: accent,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Reinsnappen', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
