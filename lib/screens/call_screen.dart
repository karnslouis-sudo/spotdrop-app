import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../services/github_service.dart';
import '../services/theme_service.dart';
import '../widgets/glass_container.dart';

class CallScreen extends StatefulWidget {
  final String? callId;
  final String callerName;
  final bool isIncoming;
  final VoidCallback onEndCall;

  const CallScreen({
    super.key,
    this.callId,
    required this.callerName,
    this.isIncoming = false,
    required this.onEndCall,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  Timer? _callDurationTimer;
  Timer? _callSyncTimer;
  int _callSeconds = 0;
  bool _isMuted = false;
  bool _isSpeaker = true;
  bool _hasConnected = false;

  // Live Push-To-Talk Voice Transmission
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final AudioPlayer _callAudioPlayer = AudioPlayer();
  bool _isTalking = false;
  String? _talkRecordingPath;
  int _lastPlayedAudioTimestamp = 0;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    if (widget.isIncoming) {
      _startCallTimer();
    } else {
      // Outgoing call: poll calls.json until receiver accepts
      _pollCallState();
    }

    // Call sync loop (every 2s): checks if other party answered, hung up, or sent voice
    _callSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _syncCallEvents());
  }

  @override
  void dispose() {
    _waveController.dispose();
    _callDurationTimer?.cancel();
    _callSyncTimer?.cancel();
    _voiceRecorder.dispose();
    _callAudioPlayer.dispose();
    super.dispose();
  }

  void _startCallTimer() {
    if (_hasConnected) return;
    setState(() => _hasConnected = true);
    HapticFeedback.lightImpact();
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  Future<void> _pollCallState() async {
    if (widget.callId == null) {
      _startCallTimer();
      return;
    }
    final status = await GitHubService().getCallStatus(widget.callId!);
    if (status == 'active') {
      _startCallTimer();
    }
  }

  Future<void> _syncCallEvents() async {
    if (widget.callId == null) return;
    final service = GitHubService();

    // 1. Status prüfen
    final status = await service.getCallStatus(widget.callId!);
    if (status == 'ended' && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📞 Anruf wurde beendet.'),
          duration: Duration(seconds: 2),
        ),
      );
      widget.onEndCall();
      return;
    } else if (status == 'active' && !_hasConnected) {
      _startCallTimer();
    }

    // 2. Eingehende Sprach-Chunks im Call abspielen
    final audioData = await service.fetchCallAudio(widget.callId!);
    if (audioData != null) {
      final sender = audioData['last_sender'] as String?;
      final ts = (audioData['last_audio_timestamp'] as num?)?.toInt() ?? 0;
      final base64Chunk = audioData['last_audio_base64'] as String?;

      if (sender != service.userName && ts > _lastPlayedAudioTimestamp && base64Chunk != null && base64Chunk.isNotEmpty) {
        _lastPlayedAudioTimestamp = ts;
        try {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/call_voice_$ts.m4a');
          await file.writeAsBytes(base64Decode(base64Chunk));
          await _callAudioPlayer.play(DeviceFileSource(file.path));
        } catch (_) {}
      }
    }
  }

  // PUSH-TO-TALK VOICE STREAM
  Future<void> _startTalking() async {
    if (_isMuted || widget.callId == null) return;
    HapticFeedback.mediumImpact();
    try {
      final hasPerm = await _voiceRecorder.hasPermission();
      if (!hasPerm) return;

      final temp = await getTemporaryDirectory();
      _talkRecordingPath = '${temp.path}/ptt_${DateTime.now().millisecondsSinceEpoch}.m4a';

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      );

      await _voiceRecorder.start(config, path: _talkRecordingPath!);
      setState(() => _isTalking = true);
    } catch (_) {}
  }

  Future<void> _stopTalking() async {
    if (!_isTalking) return;
    HapticFeedback.lightImpact();
    setState(() => _isTalking = false);

    try {
      final path = await _voiceRecorder.stop();
      final filePath = path ?? _talkRecordingPath;
      if (filePath != null && widget.callId != null) {
        final file = File(filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            await GitHubService().sendCallVoiceChunk(widget.callId!, bytes);
          }
        }
      }
    } catch (_) {}
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleSpeaker() {
    HapticFeedback.selectionClick();
    setState(() => _isSpeaker = !_isSpeaker);
  }

  Future<void> _hangUp() async {
    HapticFeedback.heavyImpact();
    if (widget.callId != null) {
      await GitHubService().endCall(widget.callId!);
    }
    widget.onEndCall();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService().accentColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // TOP STATUS (Schlicht & Minimalistisch)
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withOpacity(0.3)),
                    ),
                    child: Text(
                      'VOIP CREW-ANRUF',
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.callerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _hasConnected ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        !_hasConnected
                            ? (widget.isIncoming ? 'Eingehend...' : 'Klingelt...')
                            : 'Verbunden • ${_formatDuration(_callSeconds)}',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // CENTER: AVATAR & SCHLICHTE SPRACH-WELLE
              Column(
                children: [
                  AnimatedBuilder(
                    animation: _waveController,
                    builder: (context, child) {
                      final scale = 1.0 + (_waveController.value * (_isTalking ? 0.12 : 0.05));
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withOpacity(0.1),
                            border: Border.all(
                              color: _isTalking
                                  ? Colors.greenAccent
                                  : accent.withOpacity(0.4),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isTalking ? Colors.greenAccent : accent).withOpacity(0.25),
                                blurRadius: 25 * scale,
                              ),
                            ],
                          ),
                          child: Center(
                            child: CircleAvatar(
                              radius: 46,
                              backgroundColor: const Color(0xFF6366F1),
                              child: Text(
                                widget.callerName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Schlichte 7-Balken Sprachanzeige
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(7, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 4,
                        height: _hasConnected
                            ? (_isTalking ? 24.0 - ((i % 3) * 6) : 10.0 + ((i % 2) * 5))
                            : 4.0,
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        decoration: BoxDecoration(
                          color: _isTalking
                              ? Colors.greenAccent
                              : accent.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),

                  // Push-to-Talk "SPRECHEN" Button (Live Walkie-Talkie im Call)
                  GestureDetector(
                    onTapDown: (_) => _startTalking(),
                    onTapUp: (_) => _stopTalking(),
                    onTapCancel: () => _stopTalking(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      decoration: BoxDecoration(
                        color: _isTalking
                            ? Colors.greenAccent
                            : const Color(0xFF161E2E),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _isTalking
                              ? Colors.greenAccent
                              : accent.withOpacity(0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          if (_isTalking)
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.4),
                              blurRadius: 16,
                            ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.mic,
                            color: _isTalking ? Colors.black : Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isTalking ? 'WIRD GESENDET...' : 'GEDRÜCKT HALTEN ZUM SPRECHEN',
                            style: TextStyle(
                              color: _isTalking ? Colors.black : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // BOTTOM CONTROLS (Schlicht & Übersichtlich)
              LiquidGlassCard(
                borderRadius: 36,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Mute
                    IconButton(
                      icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, size: 26),
                      color: _isMuted ? Colors.redAccent : Colors.white,
                      onPressed: _toggleMute,
                      tooltip: 'Stummschalten',
                    ),

                    // End Call (Großer roter Button)
                    GestureDetector(
                      onTap: _hangUp,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withOpacity(0.5),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.call_end, color: Colors.white, size: 28),
                        ),
                      ),
                    ),

                    // Speaker
                    IconButton(
                      icon: Icon(_isSpeaker ? Icons.volume_up : Icons.volume_down, size: 26),
                      color: _isSpeaker ? accent : Colors.white,
                      onPressed: _toggleSpeaker,
                      tooltip: 'Lautsprecher',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
