import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/github_service.dart';
import 'services/accident_detection_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'screens/privacy_consent_screen.dart';
import 'screens/group_select_screen.dart';
import 'screens/map_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/vault_screen.dart';
import 'screens/call_screen.dart';
import 'widgets/glass_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GitHubService().initialize();
  await NotificationService().initialize();
  await ThemeService().initialize();

  final prefs = await SharedPreferences.getInstance();
  final hasLegalConsent = prefs.getBool('spotdrop_legal_consent') ?? false;

  runApp(SpotdropApp(initialConsent: hasLegalConsent));
}

class SpotdropApp extends StatefulWidget {
  final bool initialConsent;
  const SpotdropApp({super.key, required this.initialConsent});

  @override
  State<SpotdropApp> createState() => _SpotdropAppState();
}

class _SpotdropAppState extends State<SpotdropApp> {
  late bool _hasConsent;

  @override
  void initState() {
    super.initState();
    _hasConsent = widget.initialConsent;
  }

  bool get _hasGroup => 
      GitHubService().userName != null && 
      GitHubService().userName!.isNotEmpty && 
      GitHubService().currentGroup != null;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService(),
      builder: (context, _) {
        final accent = ThemeService().accentColor;

        return MaterialApp(
          title: 'Spotdrop',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF080B11),
            colorScheme: ColorScheme.dark(
              primary: accent,
              secondary: const Color(0xFF6366F1),
              surface: const Color(0xFF101522),
            ),
            useMaterial3: true,
          ),
          home: !_hasConsent
              ? PrivacyConsentScreen(onAccepted: () => setState(() => _hasConsent = true))
              : _hasGroup
                  ? MainNavigationShell(onChangeGroup: () => setState(() {}))
                  : GroupSelectScreen(onGroupReady: () => setState(() {})),
        );
      },
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
  final Set<String> _notifiedAlertIds = {};
  String? _lastNotifiedChatMsgId;
  String? _activeIncomingCallId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdatePromptOnce();
      _initAccidentDetection();
    });

    // PUSH NOTIFICATION & LIVE EVENT WATCHER (AUCH FÜR HINTERGRUND-EVENTS)
    _notificationWatcherTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkLiveNotificationsAndBackgroundEvents();
    });
  }

  @override
  void dispose() {
    _notificationWatcherTimer?.cancel();
    AccidentDetectionService().stopMonitoring();
    _pageController.dispose();
    super.dispose();
  }

  // ACCIDENT DETECTION INITIALISIEREN
  void _initAccidentDetection() {
    AccidentDetectionService().startMonitoring(
      onCrashDetected: _showEmergencyCountdownDialog,
      onTick: (secondsLeft) {},
    );
  }

  // 30 SEKUNDEN NOTFALL COUNTDOWN DIALOG
  void _showEmergencyCountdownDialog() {
    int remaining = 30;
    Timer? countdownTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (remaining > 1) {
              setDialogState(() => remaining--);
            } else {
              t.cancel();
              if (mounted && Navigator.canPop(ctx)) {
                Navigator.pop(ctx);
                _showSosSentConfirmation();
              }
            }
          });

          return AlertDialog(
            backgroundColor: const Color(0xFF220A0E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: Colors.redAccent, width: 2),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 30),
                SizedBox(width: 8),
                Text('AUFPRALL ERKANNT!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withOpacity(0.2),
                    border: Border.all(color: Colors.redAccent, width: 3),
                  ),
                  child: Center(
                    child: Text(
                      '$remaining',
                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Ein schwerer Sturz oder Aufprall wurde gemessen.\n'
                  'Ein automatischer SOS-Notruf mit deinen Live-GPS-Koordinaten wird an deine Crew gesendet!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFA3),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    countdownTimer?.cancel();
                    AccidentDetectionService().cancelEmergency();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notfall-Alarm abgebrochen. Fehlalarm verhindert.')),
                    );
                  },
                  icon: const Icon(Icons.check_circle, color: Colors.black),
                  label: const Text('ICH BIN OK (Alarm abbrechen)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          );
        },
      ),
    ).then((_) => countdownTimer?.cancel());
  }

  void _showSosSentConfirmation() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 8),
        content: Text('🚨 SOS-NOTRUF & GPS-STANDORT ERFOLGREICH AN CREW GESENDET!', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // SYSTEM PUSH NOTIFICATIONS FÜR UNFALL, ANRUF, CHAT & AKKU
  Future<void> _checkLiveNotificationsAndBackgroundEvents() async {
    final service = GitHubService();
    if (service.currentGroup == null) return;
    final myName = service.userName;

    // 1. EINGEHENDE UNFALL-NOTRUFE DER CREW
    try {
      final alerts = await service.fetchEmergencyAlerts();
      for (final a in alerts) {
        final alertId = a['id']?.toString() ?? '';
        final author = a['user'] ?? 'Crew';
        final details = a['details'] ?? 'Unfall erkannt!';
        final lat = (a['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (a['lng'] as num?)?.toDouble() ?? 0.0;

        if (author != myName && !_notifiedAlertIds.contains(alertId)) {
          _notifiedAlertIds.add(alertId);
          // System Push-Notification mit maximaler Priorität!
          await NotificationService().showEmergencyNotification(
            author: author,
            details: details,
            lat: lat,
            lng: lng,
          );
          if (mounted) {
            _showNotificationBanner(
              title: '🚨 UNFALL-NOTRUF: $author',
              message: '$details (GPS: $lat, $lng)',
              color: Colors.redAccent,
              icon: Icons.emergency,
            );
          }
        }
      }
    } catch (_) {}

    // 2. EINGEHENDE ANRUFE (VOIP)
    try {
      final call = await service.checkIncomingCall();
      if (call != null && _activeIncomingCallId != call['id']) {
        _activeIncomingCallId = call['id'];
        final caller = call['caller'] ?? 'Jemand';

        // System Notification für Anruf
        await NotificationService().showIncomingCallNotification(
          caller: caller,
          callId: call['id'],
        );

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF101624),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: ThemeService().accentColor, width: 1.5),
              ),
              title: Row(
                children: [
                  Icon(Icons.phone_in_talk, color: ThemeService().accentColor),
                  const SizedBox(width: 8),
                  Text('$caller ruft an...', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text('$caller startet einen Spotdrop VoIP Crew-Anruf.', style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await service.endCall(call['id']);
                  },
                  icon: const Icon(Icons.call_end, color: Colors.redAccent),
                  label: const Text('Ablehnen', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeService().accentColor,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await service.answerCall(call['id']);
                    if (mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CallScreen(
                            callerName: caller,
                            isIncoming: true,
                            onEndCall: () => Navigator.pop(context),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.call, color: Colors.black),
                  label: const Text('Annehmen', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {}

    // 3. NEUE CHAT-NACHRICHTEN (WENN USER IN ANDEREM TAB ODER MINIMIERT)
    try {
      final msgs = await service.fetchChatMessages();
      if (msgs.isNotEmpty) {
        final lastMsg = msgs.last;
        final msgId = lastMsg['id']?.toString() ?? '';
        final author = lastMsg['author'] as String?;
        final text = lastMsg['text'] as String? ?? 'Mediennachricht';

        if (_lastNotifiedChatMsgId != null && _lastNotifiedChatMsgId != msgId && author != myName) {
          _lastNotifiedChatMsgId = msgId;
          if (_currentIndex != 1) { // Nur benachrichtigen wenn nicht im Chat-Tab!
            await NotificationService().showChatNotification(
              author: author ?? 'Crew',
              text: text,
            );
          }
        } else if (_lastNotifiedChatMsgId == null) {
          _lastNotifiedChatMsgId = msgId;
        }
      }
    } catch (_) {}

    // 4. AKKU < 5% WARNUNGEN
    try {
      final locations = await service.fetchMemberLocations();
      for (final loc in locations) {
        final user = loc['user'] as String?;
        final battery = (loc['battery'] as num?)?.toInt() ?? 100;

        if (user != null && user != myName && battery <= 5) {
          if (!_notifiedLowBatteryUsers.contains(user)) {
            _notifiedLowBatteryUsers.add(user);
            await NotificationService().showBatteryNotification(
              user: user,
              batteryLevel: battery,
            );
            if (mounted) {
              _showNotificationBanner(
                title: '⚠️ Akku-Warnung: $user',
                message: '$user hat nur noch $battery% Akku!',
                color: Colors.redAccent,
                icon: Icons.battery_alert,
              );
            }
          }
        }
      }
    } catch (_) {}
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
        content: LiquidGlassCard(
          borderRadius: 20,
          borderColor: color.withOpacity(0.5),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
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

  // UPDATE POP-UP SOLL NUR EINMAL PRO VERSION KOMMEN!
  Future<void> _checkUpdatePromptOnce({bool forceManualCheck = false}) async {
    final update = await GitHubService().checkForUpdate();
    if (!mounted || update == null) {
      if (forceManualCheck && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App ist auf dem neuesten Stand! (v1.0.4)')),
        );
      }
      return;
    }

    final remoteVersion = update['latest_version'] as String?;
    final prefs = await SharedPreferences.getInstance();
    final dismissedVersion = prefs.getString('spotdrop_dismissed_update_version');

    // Wenn der User diese Version bereits gesehen hat und kein manueller Check ist: ignorieren!
    if (!forceManualCheck && dismissedVersion == remoteVersion) {
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF121722),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: ThemeService().accentColor, width: 1.5),
          ),
          title: Row(
            children: [
              Icon(Icons.rocket_launch, color: ThemeService().accentColor),
              const SizedBox(width: 8),
              const Text('Neues Update da!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version $remoteVersion steht bereit (Aktuell: ${GitHubService.appVersion}).', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Text(update['notes'] ?? '', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Lade die neueste Version direkt vom GitHub Repository herunter:', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // Nur einmal merken!
                if (remoteVersion != null) {
                  await prefs.setString('spotdrop_dismissed_update_version', remoteVersion);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Später', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeService().accentColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                if (remoteVersion != null) {
                  await prefs.setString('spotdrop_dismissed_update_version', remoteVersion);
                }
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
    }
  }

  // DESIGN PERSONALISIEREN (AKZENTFARBEN & GLAS-STILE)
  void _openDesignCustomizer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = ThemeService();
          final currentAccent = theme.accentColor;
          final currentStyle = theme.glassStyle;

          return LiquidGlassCard(
            borderRadius: 28,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.palette, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Design Personalisieren', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Akzentfarbe wählen:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                // Farbwähler
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: ThemeService.availableColors.map((item) {
                    final color = item['color'] as Color;
                    final isSelected = currentAccent.value == color.value;

                    return GestureDetector(
                      onTap: () async {
                        await theme.setAccentColor(color);
                        setSheetState(() {});
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(color: color.withOpacity(0.4), blurRadius: 10),
                          ],
                        ),
                        child: isSelected ? const Center(child: Icon(Icons.check, color: Colors.black, size: 20)) : null,
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),
                const Text('Liquid Glass Stil:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                // Stilwähler
                Column(
                  children: ThemeService.availableStyles.map((item) {
                    final isSelected = currentStyle == item['id'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: isSelected ? currentAccent : Colors.white12),
                        ),
                        tileColor: const Color(0xFF141926).withOpacity(0.8),
                        title: Text(item['name']!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(item['desc']!, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                        trailing: isSelected ? Icon(Icons.check_circle, color: currentAccent) : null,
                        onTap: () async {
                          await theme.setGlassStyle(item['id']!);
                          setSheetState(() {});
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final service = GitHubService();
    final accent = ThemeService().accentColor;

    return Scaffold(
      extendBody: false, // Keine Überlappung der Bottom-Bar mit Bildinhalten
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1420),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [const Color(0xFF6366F1), accent]),
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
                  style: TextStyle(fontSize: 10, color: accent, fontFamily: 'monospace'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined, color: Colors.white, size: 20),
            onPressed: _openDesignCustomizer,
            tooltip: 'Design Personalisieren',
          ),
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
            onPressed: () {
              AccidentDetectionService().testTriggerEmergency(
                _showEmergencyCountdownDialog,
                (s) {},
              );
            },
            tooltip: 'Notfall / Unfall Test',
          ),
          IconButton(
            icon: Icon(Icons.rocket_launch, color: accent, size: 19),
            onPressed: () => _checkUpdatePromptOnce(forceManualCheck: true),
            tooltip: 'Updates prüfen',
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.grey, size: 20),
            onPressed: _confirmLogout,
            tooltip: 'Abmelden',
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

      // DOCKING LIQUID GLASS NAVIGATION BAR
      bottomNavigationBar: Container(
        color: const Color(0xFF080B11),
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 6),
        child: LiquidGlassCard(
          borderRadius: 28,
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
    );
  }

  Widget _buildNavItem(int index, IconData outlineIcon, IconData filledIcon, String label) {
    final isSelected = _currentIndex == index;
    final accent = ThemeService().accentColor;

    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accent : Colors.transparent,
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
