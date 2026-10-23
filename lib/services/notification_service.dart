import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final AudioPlayer _ringPlayer = AudioPlayer();
  Timer? _vibrateTimer;
  bool _isRinging = false;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
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

    // 1. ANDROID 13+ BERECHTIGUNGEN & KANÄLE
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
    } catch (e) {
      debugPrint('Android notification channel error: $e');
    }

    // 2. APPLE / IOS BERECHTIGUNG ANFRAGEN (ESSENTIELL FÜR IPHONE!)
    try {
      final iosImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosImplementation?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );
      debugPrint('iOS Notifications Granted: $granted');
    } catch (e) {
      debugPrint('iOS notification permission error: $e');
    }

    _isInitialized = true;
  }

  // ==========================================================================
  // RING-TON GENERATOR (SYNTHETISCHER KLINGELTON OHNE EXTERNE ASSETS)
  // ==========================================================================
  static Uint8List _generateTelephoneRingToneWav() {
    const sampleRate = 8000;
    const durationMs = 1200; // 1.2s Ring-Intervall
    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setUint8(8, 0x57);  // 'W'
    buffer.setUint8(9, 0x41);  // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6d); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    buffer.setUint16(20, 1, Endian.little);  // AudioFormat (1 for PCM)
    buffer.setUint16(22, 1, Endian.little);  // NumChannels (1 mono)
    buffer.setUint32(24, sampleRate, Endian.little); // SampleRate
    buffer.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    buffer.setUint16(32, 2, Endian.little);  // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample

    // data subchunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, dataSize, Endian.little);

    // Audio samples: European Ringback Tone (425 Hz) with 0.8s on, 0.4s pause
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      int sample = 0;
      if (t < 0.8) {
        // Sine wave tone
        final wave = math.sin(2 * math.pi * 425 * t) * 0.7;
        sample = (wave * 32767).round().clamp(-32768, 32767);
      }
      buffer.setInt16(44 + (i * 2), sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  // ==========================================================================
  // KLINGELN & VIBRATION STARTEN BEI EINGEHENDEM ANRUF
  // ==========================================================================
  Future<void> startIncomingCallRing({required String caller, required String callId}) async {
    await showIncomingCallNotification(caller: caller, callId: callId);
    if (_isRinging) return;
    _isRinging = true;

    try {
      final wavBytes = _generateTelephoneRingToneWav();
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(BytesSource(wavBytes), volume: 1.0);
    } catch (_) {}

    _vibrateTimer?.cancel();
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  Future<void> stopIncomingCallRing() async {
    _isRinging = false;
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
    try {
      await _ringPlayer.stop();
    } catch (_) {}
  }

  // ==========================================================================
  // 1. DRINGLICHE UNFALL-BENACHRICHTIGUNG (LOCKSCREEN + TON + VIBRATION)
  // ==========================================================================
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
      presentBanner: true,
      presentList: true,
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

  // ==========================================================================
  // 2. EINGEHENDER ANRUF BENACHRICHTIGUNG (KLINGELN)
  // ==========================================================================
  Future<void> showIncomingCallNotification({
    required String caller,
    required String callId,
  }) async {
    await initialize();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'call_channel',
      '📞 Spotdrop VoIP Anrufe',
      channelDescription: 'Eingehender VoIP Audio-Anruf',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.call,
      styleInformation: BigTextStyleInformation(''),
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    const NotificationDetails detailsPlatform = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      888,
      '📞 Eingehender Anruf',
      '$caller ruft dich an... Antippen zum Annehmen!',
      detailsPlatform,
    );
  }

  // ==========================================================================
  // 3. CHAT-NACHRICHT BENACHRICHTIGUNG
  // ==========================================================================
  Future<void> showChatNotification({
    required String author,
    required String text,
  }) async {
    await initialize();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_channel',
      '💬 Chat-Nachrichten',
      channelDescription: 'Neue Nachrichten der Crew',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const NotificationDetails detailsPlatform = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      777,
      '💬 $author (Spotdrop)',
      text,
      detailsPlatform,
    );
  }

  // ==========================================================================
  // 4. BATTERIE-WARNUNG (< 5%)
  // ==========================================================================
  Future<void> showBatteryNotification({
    required String user,
    required int batteryLevel,
  }) async {
    await initialize();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_channel',
      '🔋 Akku-Warnungen',
      channelDescription: 'Warnung bei kritischem Akkustand von Freunden',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
    );

    const NotificationDetails detailsPlatform = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      666,
      '🪫 Kritischer Akku: $user',
      'Der Akku von $user ist bei $batteryLevel%! Standort könnte bald offline gehen.',
      detailsPlatform,
    );
  }
}
