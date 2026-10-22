import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/github_service.dart';
import 'screens/group_select_screen.dart';
import 'screens/map_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/vault_screen.dart';
import 'widgets/glass_container.dart';

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
        scaffoldBackgroundColor: const Color(0xFF080B11),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFA3),
          secondary: Color(0xFF6366F1),
          surface: Color(0xFF101522),
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
  final PageController _pageController = PageController(initialPage: 0);
  int _currentIndex = 0;
  Timer? _notificationWatcherTimer;
  final Set<String> _notifiedLowBatteryUsers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatePrompt();
    });

    // WATCHER FÜR NOTIFICATIONS (AKKU UNTER 5%, NEUE CHATS USW.)
    _notificationWatcherTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _checkLiveNotifications();
    });
  }

  @override
  void dispose() {
    _notificationWatcherTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // PRÜFT AKKU ANDERER PERSONEN & LÖST NOTIFICATION AUS WENN < 5%
  Future<void> _checkLiveNotifications() async {
    final service = GitHubService();
    if (service.currentGroup == null) return;

    final locations = await service.fetchMemberLocations();
    for (final loc in locations) {
      final user = loc['user'] as String?;
      final battery = (loc['battery'] as num?)?.toInt() ?? 100;

      if (user != null && user != service.userName && battery <= 5) {
        if (!_notifiedLowBatteryUsers.contains(user)) {
          _notifiedLowBatteryUsers.add(user);
          if (mounted) {
            _showNotificationBanner(
              title: '⚠️ Akku-Warnung: $user',
              message: '$user hat nur noch $battery% Akku! Eventuell bald offline.',
              color: Colors.redAccent,
              icon: Icons.battery_alert,
            );
          }
        }
      }
    }
  }

  void _showNotificationBanner({
    required String title,
    required String message,
    required Color color,
    required IconData icon,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 20),
        duration: const Duration(seconds: 5),
        content: GlassContainer(
          borderRadius: 20,
          borderColor: color.withOpacity(0.5),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(message, style: TextStyle(color: Colors.grey.shade300, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // BESTÄTIGUNGS-MODAL BEIM ABMELDEN
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141926),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: Colors.white.withOpacity(0.12))),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.amberAccent),
            SizedBox(width: 8),
            Text('Abmelden?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Text(
          'Möchtest du dich wirklich abmelden?\nDein Name und deine Gruppen-Verbindung werden auf diesem Gerät zurückgesetzt.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final service = GitHubService();
              await service.setCurrentGroup(null);
              await service.setUserName('');
              widget.onChangeGroup();
            },
            child: const Text('Ja, Abmelden', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // UPDATE POP-UP ZU GITHUB
  Future<void> _checkUpdatePrompt({bool showNoUpdateNotice = false}) async {
    final update = await GitHubService().checkForUpdate();
    if (!mounted) return;

    if (update != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF121722),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF00FFA3), width: 1.5)),
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
              Text('Version ${update['latest_version']} steht bereit (Aktuell: ${GitHubService.appVersion}).', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Text(update['notes'] ?? '', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Lade die neueste Version direkt vom GitHub Repository herunter:', style: TextStyle(color: Colors.white70, fontSize: 11)),
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
      extendBody: true, // Erlaubt Floating Liquid Glass Navigation Bar
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1420).withOpacity(0.85),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF00FFA3)]),
              ),
              child: const Text('SD', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.currentGroupName ?? 'Spotdrop',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${service.userName ?? "Du"} • Code: ${service.currentGroupCode ?? ""}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF00FFA3), fontFamily: 'monospace'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.rocket_launch, color: Color(0xFF00FFA3), size: 19),
            onPressed: () => _checkUpdatePrompt(showNoUpdateNotice: true),
            tooltip: 'Updates prüfen',
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.grey, size: 20),
            onPressed: _confirmLogout,
            tooltip: 'Abmelden (mit Bestätigung)',
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: [
          const MapScreen(),
          HubScreen(onChangeGroup: widget.onChangeGroup),
          const VaultScreen(),
        ],
      ),

      // LIQUID GLASS FLOATING NAVIGATION BAR
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: GlassContainer(
            borderRadius: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.map_outlined, Icons.map, 'Spot-Map'),
                _buildNavItem(1, Icons.chat_bubble_outline, Icons.chat_bubble, 'Crew-Hub'),
                _buildNavItem(2, Icons.photo_library_outlined, Icons.photo_library, 'Snap-Vault'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData outlineIcon, IconData filledIcon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00FFA3) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? filledIcon : outlineIcon,
              size: 20,
              color: isSelected ? Colors.black : Colors.white60,
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
