// lib/services/realtime_service.dart
// Echtzeit-Nachrichten, Sprachnachrichten & Bilder via Cloud Firestore
// Mit Animations-Triggern

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class RealtimeMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final String type; // 'text' | 'voice' | 'image' | 'system'
  final DateTime timestamp;
  final bool isNew; // für Animation

  const RealtimeMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.type,
    required this.timestamp,
    this.isNew = false,
  });

  factory RealtimeMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RealtimeMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      content: data['content'] ?? '',
      type: data['type'] ?? 'text',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isNew: false,
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
      };
}

class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Nachrichten Stream (Echtzeit) ──────────────────────────────────────────
  Stream<List<RealtimeMessage>> messagesStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(100)
        .snapshots()
        .map((snap) => snap.docs.map(RealtimeMessage.fromFirestore).toList());
  }

  // ─── Neue Nachricht senden ───────────────────────────────────────────────────
  Future<String> sendMessage({
    required String groupId,
    required String senderId,
    required String senderName,
    required String content,
    required String type,
  }) async {
    final ref = await _db
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Gruppe updaten (letzter Eintrag)
    await _db.collection('groups').doc(groupId).set({
      'lastMessage': content,
      'lastMessageType': type,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderName': senderName,
    }, SetOptions(merge: true));

    return ref.id;
  }

  // ─── Sprachnachricht hochladen (base64 in Firestore) ────────────────────────
  Future<String> sendVoiceNote({
    required String groupId,
    required String senderId,
    required String senderName,
    required File audioFile,
  }) async {
    final bytes = await audioFile.readAsBytes();
    final b64 = base64Encode(bytes);

    return sendMessage(
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      content: b64,
      type: 'voice',
    );
  }

  // ─── Bild hochladen (base64 in Firestore) ───────────────────────────────────
  Future<String> sendImage({
    required String groupId,
    required String senderId,
    required String senderName,
    required File imageFile,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final b64 = base64Encode(bytes);

    return sendMessage(
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      content: b64,
      type: 'image',
    );
  }

  // ─── Tipp-Indikator ──────────────────────────────────────────────────────────
  Future<void> setTyping(String groupId, String userId, String userName, bool isTyping) async {
    await _db.collection('groups').doc(groupId).collection('typing').doc(userId).set({
      'name': userName,
      'isTyping': isTyping,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<String>> typingUsersStream(String groupId, String myUserId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('typing')
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d.id != myUserId && d.data()['isTyping'] == true)
            .map((d) => d.data()['name'] as String)
            .toList());
  }

  // ─── Gruppen ────────────────────────────────────────────────────────────────
  Future<void> ensureGroupExists(String groupId, String groupName) async {
    final doc = await _db.collection('groups').doc(groupId).get();
    if (!doc.exists) {
      await _db.collection('groups').doc(groupId).set({
        'name': groupName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ─── User online/offline ─────────────────────────────────────────────────────
  Future<void> setOnlineStatus(String userId, bool online) async {
    await _db.collection('users').doc(userId).set({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<bool> onlineStream(String userId) {
    return _db.collection('users').doc(userId).snapshots()
        .map((s) => s.data()?['online'] == true);
  }
}
