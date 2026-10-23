// lib/services/notification_service.dart
// Push Notifications: FCM (Foreground + Background) + CallKit

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

// Background Handler (top-level Funktion!)
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Eingehender Anruf im Hintergrund → nativen Call-Screen zeigen
  if (message.data['type'] == 'incoming_call') {
    final callId = message.data['callId'] ?? '';
    final callerName = message.data['callerName'] ?? 'Unbekannt';
    final callerAvatar = message.data['callerAvatar'] ?? '';

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Spotdrop',
      avatar: callerAvatar.isNotEmpty ? callerAvatar : null,
      handle: callerName,
      type: 0,
      textAccept: 'Annehmen',
      textDecline: 'Ablehnen',
      backgroundColor: '#0A0F1E',
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        isShowCallback: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0A0F1E',
        actionColor: '#00FFA3',
        textColor: '#FFFFFF',
      ),
      duration: 30000,
      extra: {'callId': callId},
      headers: {'callId': callId},
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Verpasster Anruf',
        callbackText: 'Zurückrufen',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  // Notification Channels
  static const _chatChannelId = 'spotdrop_chat';
  static const _callChannelId = 'spotdrop_calls';
  static const _emergencyChannelId = 'spotdrop_emergency';

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  final _notifController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get notificationEvents => _notifController.stream;

  // ─── Initialisierung ────────────────────────────────────────────────────────
  Future<void> initialize() async {
    // Firebase Messaging Berechtigungen anfragen
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );

    // Lokale Notifications initialisieren
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );

    await _localNotifs.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Android Channels anlegen
    await _createAndroidChannels();

    // FCM Token holen
    _fcmToken = await messaging.getToken();
    debugPrint('FCM Token: $_fcmToken');

    // Token Refresh
    messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
    });

    // Background Handler registrieren
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    // Foreground Handler
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // App aus Benachrichtigung geöffnet
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // Initial Message (App war beendet, via Notification geöffnet)
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _onMessageOpenedApp(initialMessage);
    }

    // iOS Foreground Presentation Options
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // ─── Android Notification Channels ──────────────────────────────────────────
  Future<void> _createAndroidChannels() async {
    final plugin = _localNotifs.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;

    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      _chatChannelId,
      'Spotdrop Nachrichten',
      description: 'Chat-Nachrichten von deiner Crew',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('notification'),
    ));

    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      _callChannelId,
      'Spotdrop Anrufe',
      description: 'Eingehende Anrufe',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('ringtone'),
      enableVibration: true,
    ));

    await plugin.createNotificationChannel(const AndroidNotificationChannel(
      _emergencyChannelId,
      'Spotdrop Notfall',
      description: 'Notfall-Alarme',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('emergency'),
      enableVibration: true,
    ));
  }

  // ─── Foreground Message Handler ──────────────────────────────────────────────
  void _onForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] ?? 'chat';

    if (type == 'incoming_call') {
      // Nativer Call Screen
      _notifController.add({'type': 'incoming_call', ...data});
    } else if (type == 'chat' || type == 'voice' || type == 'image') {
      // Lokale Notification
      showChatNotification(
        title: message.notification?.title ?? data['senderName'] ?? 'Spotdrop',
        body: message.notification?.body ?? _getBodyForType(type, data),
        groupId: data['groupId'],
      );
      _notifController.add({'type': type, ...data});
    } else if (type == 'emergency') {
      showEmergencyNotification(
        title: message.notification?.title ?? '🚨 NOTFALL',
        body: message.notification?.body ?? 'Dringender Alarm!',
      );
    }
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    _notifController.add({'type': 'app_opened', ...message.data});
  }

  String _getBodyForType(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'voice': return '🎤 Sprachnachricht';
      case 'image': return '📷 Bild';
      default: return data['content'] ?? '';
    }
  }

  // ─── Lokale Notifications ────────────────────────────────────────────────────
  Future<void> showChatNotification({
    required String title,
    required String body,
    String? groupId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _chatChannelId,
      'Spotdrop Nachrichten',
      channelDescription: 'Chat-Nachrichten',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifs.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: groupId,
    );
  }

  Future<void> showEmergencyNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _emergencyChannelId,
      'Spotdrop Notfall',
      channelDescription: 'Notfall-Alarme',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    await _localNotifs.show(
      0,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    _notifController.add({'type': 'tap', 'payload': response.payload});
  }

  void dispose() {
    _notifController.close();
  }
}
