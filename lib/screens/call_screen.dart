import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/theme_service.dart';
import '../widgets/glass_container.dart';

class CallScreen extends StatefulWidget {
  final String callerName;
  final bool isIncoming;
  final VoidCallback onEndCall;

  const CallScreen({
    super.key,
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
  int _callSeconds = 0;
  bool _isMuted = false;
  bool _isSpeaker = true;
  bool _hasConnected = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Bei eingehendem Anruf oder nach kurzem Freizeichen verbinden
    if (widget.isIncoming) {
      _startCallTimer();
    } else {
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) _startCallTimer();
      });
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _callDurationTimer?.cancel();
    super.dispose();
  }

  void _startCallTimer() {
    setState(() => _hasConnected = true);
    HapticFeedback.lightImpact();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    setState(() => _isMuted = !_isMuted);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(_isMuted ? '🔇 Mikrofon stummgeschaltet' : '🎙️ Mikrofon aktiv'),
      ),
    );
  }

  void _toggleSpeaker() {
    HapticFeedback.selectionClick();
    setState(() => _isSpeaker = !_isSpeaker);
  }

  void _hangUp() {
    HapticFeedback.heavyImpact();
    widget.onEndCall();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService().accentColor;

    return Scaffold(
      backgroundColor: const Color(0xFF080B11),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Status
              Column(
                children: [
                  Text(
                    'SPOTDROP VOIP AUDIO-CALL',
                    style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Text(widget.callerName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    !_hasConnected ? 'Verbinde mit Server...' : _formatDuration(_callSeconds),
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontFamily: 'monospace'),
                  ),
                ],
              ),

              // Animated Soundwave Avatar & Voice Visualizer
              Column(
                children: [
                  AnimatedBuilder(
                    animation: _waveController,
                    builder: (context, child) {
                      final scale = 1.0 + (_waveController.value * 0.15);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withOpacity(0.12),
                            border: Border.all(
                              color: accent.withOpacity(0.5 * (1 - _waveController.value)),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withOpacity(0.3),
                                blurRadius: 30 * scale,
                              ),
                            ],
                          ),
                          child: Center(
                            child: CircleAvatar(
                              radius: 46,
                              backgroundColor: const Color(0xFF6366F1),
                              child: Text(
                                widget.callerName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  
                  // Live Equalizer Visualizer Bars
                  AnimatedBuilder(
                    animation: _waveController,
                    builder: (context, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(16, (i) {
                          final h = _hasConnected && !_isMuted 
                              ? 6.0 + ((i % 5) * 6.0 * _waveController.value)
                              : 4.0;
                          return Container(
                            width: 3.5,
                            height: h,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),

              // Control Buttons
              LiquidGlassCard(
                borderRadius: 36,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Mute Button
                    IconButton(
                      icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, size: 28),
                      color: _isMuted ? Colors.redAccent : Colors.white,
                      onPressed: _toggleMute,
                      tooltip: 'Stummschalten',
                    ),

                    // End Call Button
                    GestureDetector(
                      onTap: _hangUp,
                      child: Container(
                        width: 65,
                        height: 65,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent,
                          boxShadow: [
                            BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 18),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.call_end, color: Colors.white, size: 30),
                        ),
                      ),
                    ),

                    // Speaker Button
                    IconButton(
                      icon: Icon(_isSpeaker ? Icons.volume_up : Icons.volume_down, size: 28),
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
