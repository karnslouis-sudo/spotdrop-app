import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Callback bei Antippen der Notification
      },
    );

    // Request Android 13+ Notification Permission
    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.createNotificationChannel(
        const AndroidNotificationChannel(
          'emergency_channel',
          '🚨 Unfall- & Notfall-Alarme',
          description: 'Dringliche Push-Benachrichtigungen bei Unfällen oder SOS-Rufen',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        ),
      );
      await androidImplementation?.createNotificationChannel(
        const AndroidNotificationChannel(
          'call_channel',
          '📞 Spotdrop VoIP Anrufe',
          description: 'Benachrichtigung bei eingehenden Audio-Anrufen',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        ),
      );
      await androidImplementation?.createNotificationChannel(
        const AndroidNotificationChannel(
          'chat_channel',
          '💬 Chat-Nachrichten',
          description: 'Benachrichtigung bei neuen Chat-Nachrichten der Crew',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
      );
    } catch (_) {}

    _isInitialized = true;
  }

  // 1. DRINGLICHE UNFALL-BENACHRICHTIGUNG (LOCKSCREEN + TON + VIBRATION)
  Future<void> showEmergencyNotification({
    required String author,
    required String details,
    required double lat,
    required double lng,
  }) async {
    await initialize();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'emergency_channel',
      '🚨 Unfall- & Notfall-Alarme',
      channelDescription: 'Dringliche Benachrichtigungen bei Unfällen',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      enableVibration: true,
      playSound: true,
      styleInformation: BigTextStyleInformation(''),
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    const NotificationDetails detailsPlatform = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      999,
      '🚨 UNFALL-ALARM: $author',
      'Schwerer Aufprall registriert! Ort: $lat, $lng. Sofort prüfen!',
      detailsPlatform,
    );
  }

  // 2. EINGEHENDER ANRUF BENACHRICHTIGUNG (KLINGELN)
  Future<void> showIncomingCallNotification({
    required String caller,
    required String callId,
  }) async {
    await initialize();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'call_channel',
      '📞 Spotdrop VoIP Anrufe',
      channelDescription: 'Eingehende VoIP-Anrufe',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.call,
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const NotificationDetails detailsPlatform = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      888,
      '📞 Eingehender Crew-Anruf',
      '$caller ruft dich über Spotdrop an...',
      detailsPlatform,
    );
  }

  // 3. CHAT-NACHRICHT BENACHRICHTIGUNG
  Future<void> showChatNotification({
    required String author,
    required String text,
  }) async {
    await initialize();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_channel',
      '💬 Chat-Nachrichten',
      channelDescription: 'Neue Chat-Nachrichten',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails detailsPlatform = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _notificationsPlugin.show(
      id,
      '💬 $author (Spotdrop)',
      text,
      detailsPlatform,
    );
  }

  // 4. AKKU-WARNUNG BENACHRICHTIGUNG
  Future<void> showBatteryNotification({
    required String user,
    required int batteryLevel,
  }) async {
    await initialize();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_channel',
      '⚠️ Akku-Warnungen',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );

    const NotificationDetails detailsPlatform = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      777,
      '⚠️ Akku-Warnung: $user',
      '$user hat nur noch $batteryLevel% Akku!',
      detailsPlatform,
    );
  }
}
