// lib/services/call_service.dart
// Echtzeit VoIP via WebRTC + Firestore Signaling
// Echter Anruf-Screen via flutter_callkit_incoming

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription? _callSub;
  String? _currentCallId;
  String? _currentUserId;
  String? _currentUserName;

  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  Stream<MediaStream> get remoteStreamEvents => _remoteStreamController.stream;

  final _callStateController = StreamController<String>.broadcast();
  Stream<String> get callStateEvents => _callStateController.stream;

  // ─── Initialisierung ────────────────────────────────────────────────────────
  Future<void> initialize(String userId, String userName) async {
    _currentUserId = userId;
    _currentUserName = userName;

    // Lausche auf eingehende Anrufe in Firestore
    _callSub?.cancel();
    _callSub = _db
        .collection('calls')
        .where('calleeId', isEqualTo: userId)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen(_onIncomingCallSnapshot);

    // FCM Foreground Handler
    FirebaseMessaging.onMessage.listen(_onFCMMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onFCMOpenedApp);

    // CallKit Events
    FlutterCallkitIncoming.onEvent.listen(_onCallkitEvent);
  }

  // ─── Anruf starten ──────────────────────────────────────────────────────────
  Future<String> startCall({
    required String callerId,
    required String callerName,
    required String calleeId,
    required String calleeName,
  }) async {
    final callId = const Uuid().v4();
    _currentCallId = callId;

    // Lokaler Stream
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    // PeerConnection aufbauen
    _peerConnection = await _createPeerConnection();
    _localStream!.getTracks().forEach((t) => _peerConnection!.addTrack(t, _localStream!));

    // Offer erstellen
    final offer = await _peerConnection!.createOffer({'offerToReceiveAudio': true});
    await _peerConnection!.setLocalDescription(offer);

    // Firestore Dokument anlegen
    await _db.collection('calls').doc(callId).set({
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'calleeId': calleeId,
      'calleeName': calleeName,
      'status': 'ringing',
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'createdAt': FieldValue.serverTimestamp(),
    });

    // ICE Candidates senden
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _db.collection('calls').doc(callId)
            .collection('callerCandidates')
            .add(candidate.toMap());
      }
    };

    // Auf Answer warten
    _db.collection('calls').doc(callId).snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      if (data['status'] == 'answered' && data['answer'] != null) {
        final answer = RTCSessionDescription(
          data['answer']['sdp'], data['answer']['type']);
        await _peerConnection!.setRemoteDescription(answer);
        _callStateController.add('connected');
      } else if (data['status'] == 'ended' || data['status'] == 'rejected') {
        _callStateController.add('ended');
        await endCall();
      }
    });

    // Callee ICE Candidates empfangen
    _db.collection('calls').doc(callId)
        .collection('calleeCandidates')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          _peerConnection!.addCandidate(RTCIceCandidate(
            data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });

    _callStateController.add('ringing');
    return callId;
  }

  // ─── Anruf annehmen ─────────────────────────────────────────────────────────
  Future<void> answerCall(String callId) async {
    _currentCallId = callId;
    final snap = await _db.collection('calls').doc(callId).get();
    final data = snap.data()!;

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    _peerConnection = await _createPeerConnection();
    _localStream!.getTracks().forEach((t) => _peerConnection!.addTrack(t, _localStream!));

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _db.collection('calls').doc(callId)
            .collection('calleeCandidates')
            .add(candidate.toMap());
      }
    };

    final offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']);
    await _peerConnection!.setRemoteDescription(offer);

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await _db.collection('calls').doc(callId).update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'answered',
    });

    // Caller ICE Candidates empfangen
    _db.collection('calls').doc(callId)
        .collection('callerCandidates')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          _peerConnection!.addCandidate(RTCIceCandidate(
            data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });

    _callStateController.add('connected');
  }

  // ─── Anruf beenden ──────────────────────────────────────────────────────────
  Future<void> endCall() async {
    if (_currentCallId != null) {
      await _db.collection('calls').doc(_currentCallId).update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
    }
    _localStream?.getTracks().forEach((t) => t.stop());
    await _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _currentCallId = null;
    _callStateController.add('idle');
  }

  // ─── Eingehender Anruf (Firestore) ──────────────────────────────────────────
  void _onIncomingCallSnapshot(QuerySnapshot snap) {
    for (final change in snap.docChanges) {
      if (change.type == DocumentChangeType.added) {
        final data = change.doc.data() as Map<String, dynamic>;
        _showIncomingCallUI(
          callId: data['callId'],
          callerName: data['callerName'] ?? 'Unbekannt',
          callerAvatar: data['callerAvatar'] ?? '',
        );
      }
    }
  }

  // ─── Nativer Anruf-Screen anzeigen ──────────────────────────────────────────
  Future<void> _showIncomingCallUI({
    required String callId,
    required String callerName,
    String callerAvatar = '',
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Spotdrop',
      avatar: callerAvatar.isNotEmpty ? callerAvatar : null,
      handle: callerName,
      type: 0, // 0 = Audio, 1 = Video
      textAccept: 'Annehmen',
      textDecline: 'Ablehnen',
      backgroundColor: '#0A0F1E',
      backgroundUrl: null,
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

  // ─── CallKit Events ─────────────────────────────────────────────────────────
  void _onCallkitEvent(CallEvent? event) async {
    if (event == null) return;
    switch (event.event) {
      case Event.ACTION_CALL_ACCEPT:
        final callId = event.body['extra']?['callId'] as String?;
        if (callId != null) {
          await answerCall(callId);
          _callStateController.add('accepted:$callId');
        }
        break;
      case Event.ACTION_CALL_DECLINE:
        final callId = event.body['id'] as String?;
        if (callId != null) {
          await _db.collection('calls').doc(callId).update({'status': 'rejected'});
        }
        break;
      case Event.ACTION_CALL_ENDED:
        await endCall();
        break;
      default:
        break;
    }
  }

  // ─── FCM Nachrichten ────────────────────────────────────────────────────────
  void _onFCMMessage(RemoteMessage message) {
    if (message.data['type'] == 'incoming_call') {
      _showIncomingCallUI(
        callId: message.data['callId'] ?? '',
        callerName: message.data['callerName'] ?? 'Unbekannt',
        callerAvatar: message.data['callerAvatar'] ?? '',
      );
    }
  }

  void _onFCMOpenedApp(RemoteMessage message) {
    // App wurde via Notification-Tap geöffnet
    if (message.data['type'] == 'incoming_call') {
      _callStateController.add('opened:${message.data['callId']}');
    }
  }

  // ─── PeerConnection Factory ──────────────────────────────────────────────────
  Future<RTCPeerConnection> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {
          'urls': 'turn:openrelay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream!);
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _callStateController.add('ended');
        endCall();
      }
    };

    return pc;
  }

  // ─── FCM Token speichern (für Push) ─────────────────────────────────────────
  Future<void> saveFCMToken(String userId) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _db.collection('users').doc(userId).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void dispose() {
    _callSub?.cancel();
    _remoteStreamController.close();
    _callStateController.close();
  }
}
