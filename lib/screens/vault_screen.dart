import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/github_service.dart';

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
            const SnackBar(
              backgroundColor: Color(0xFF00FFA3),
              content: Text('📸 Snap erfolgreich in GitHub Vault gespeichert!', style: TextStyle(color: Colors.black)),
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

  @override
  Widget build(BuildContext context) {
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
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FFA3)))
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
                              backgroundColor: const Color(0xFF00FFA3),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _snaps.length,
                      itemBuilder: (context, index) {
                        final snap = _snaps[index];
                        final url = snap['image_url'] ?? '';

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: const Color(0xFF161E2E),
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FFA3)),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF161E2E),
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                        );
                      },
                    ),

          if (_isUploading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00FFA3)),
                    SizedBox(height: 16),
                    Text(
                      'Lade Snap auf GitHub Server hoch...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : () => _takeAndUploadSnap(ImageSource.camera),
        backgroundColor: const Color(0xFF00FFA3),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.camera_alt),
        label: const Text('Reinsnappen', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
