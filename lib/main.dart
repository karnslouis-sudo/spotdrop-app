import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/github_service.dart';
import 'screens/group_select_screen.dart';
import 'screens/map_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/vault_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GitHubService().initialize();
  runApp(const SpotdropApp());
}

class SpotdropApp extends StatefulWidget {
  const SpotdropApp({super.key});

  @override
  State<SpotdropApp> createState() => _SpotdropAppState();
}

class _SpotdropAppState extends State<SpotdropApp> {
  bool get _hasGroup => 
      GitHubService().userName != null && 
      GitHubService().userName!.isNotEmpty && 
      GitHubService().currentGroup != null;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotdrop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0D14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFA3),
          secondary: Color(0xFF6366F1),
          surface: Color(0xFF121722),
        ),
        useMaterial3: true,
      ),
      home: _hasGroup
          ? MainNavigationShell(onChangeGroup: () => setState(() {}))
          : GroupSelectScreen(onGroupReady: () => setState(() {})),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  final VoidCallback onChangeGroup;
  const MainNavigationShell({super.key, required this.onChangeGroup});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  final PageController _pageController = PageController(initialPage: 1);
  int _currentIndex = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatePrompt();
    });
  }

  Future<void> _checkUpdatePrompt({bool showNoUpdateNotice = false}) async {
    final update = await GitHubService().checkForUpdate();
    if (!mounted) return;

    if (update != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF121722),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
          title: const Row(
            children: [
              Icon(Icons.rocket_launch, color: Color(0xFF00FFA3)),
              SizedBox(width: 8),
              Text('Neues Update da!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version ${update['latest_version']} steht bereit (Aktuell: ${GitHubService.appVersion}).',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                update['notes'] ?? '',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text(
                'Lade die neueste Version direkt vom GitHub Repository herunter:',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Später', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFA3),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse(update['url'] ?? 'https://github.com/karnslouis-sudo/spotdrop-app/releases');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('Zum GitHub Repo ▶', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else if (showNoUpdateNotice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App ist auf dem neuesten Stand! (v${GitHubService.appVersion})')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = GitHubService();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1420),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service.currentGroupName ?? 'Spotdrop',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              'User: ${service.userName ?? "Du"} • Code: ${service.currentGroupCode ?? ""}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF00FFA3), fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt, color: Color(0xFF00FFA3), size: 20),
            onPressed: () => _checkUpdatePrompt(showNoUpdateNotice: true),
            tooltip: 'Nach Updates suchen',
          ),
          IconButton(
            icon: const Icon(Icons.group, color: Colors.grey, size: 20),
            onPressed: () async {
              await service.setCurrentGroup(null);
              widget.onChangeGroup();
            },
            tooltip: 'Gruppe wechseln',
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: [
          const MapScreen(),
          HubScreen(onChangeGroup: () async {
            await service.setCurrentGroup(null);
            widget.onChangeGroup();
          }),
          const VaultScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        },
        backgroundColor: const Color(0xFF0F1420),
        selectedItemColor: const Color(0xFF00FFA3),
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Spot-Map'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble), label: 'Crew-Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.photo_library_outlined), activeIcon: Icon(Icons.photo_library), label: 'Snap-Vault'),
        ],
      ),
    );
  }
}
