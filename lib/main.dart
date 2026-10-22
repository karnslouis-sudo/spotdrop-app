import 'package:flutter/material.dart';
import 'services/github_service.dart';
import 'screens/map_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/vault_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GitHubService().initialize();
  runApp(const SpotdropApp());
}

class SpotdropApp extends StatelessWidget {
  const SpotdropApp({super.key});

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
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  final PageController _pageController = PageController(initialPage: 1);
  int _currentIndex = 1;

  @override
  Widget build(BuildContext context) {
    final service = GitHubService();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1420),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF00FFA3)],
                ),
              ),
              child: const Text('SD', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.currentUser ?? 'Spotdrop',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Row(
                  children: [
                    Icon(Icons.circle, size: 7, color: Color(0xFF00FFA3)),
                    SizedBox(width: 4),
                    Text(
                      'GitHub Server Live',
                      style: TextStyle(fontSize: 10, color: Color(0xFF00FFA3), fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF182133),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2A3752)),
            ),
            child: Text(
              service.repoName ?? 'spotdrop-app',
              style: const TextStyle(color: Color(0xFF00FFA3), fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: const [
          MapScreen(),
          HubScreen(),
          VaultScreen(),
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
