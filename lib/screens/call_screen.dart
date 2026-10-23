import 'dart:async';
import 'package:flutter/material.dart';
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
  late AnimationController _pulseController;
  Timer? _callDurationTimer;
  int _callSeconds = 0;
  bool _isMuted = false;
  bool _isSpeaker = true;
  bool _hasConnected = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    if (!widget.isIncoming) {
      _startCallTimer();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _callDurationTimer?.cancel();
    super.dispose();
  }

  void _startCallTimer() {
    setState(() => _hasConnected = true);
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text('SPOTDROP CREW AUDIO-CALL', style: TextStyle(color: Color(0xFF00FFA3), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Text(widget.callerName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    !_hasConnected ? 'Ruft an...' : _formatDuration(_callSeconds),
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontFamily: 'monospace'),
                  ),
                ],
              ),

              // Animated Soundwave Avatar
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 150 + (_pulseController.value * 25),
                    height: 150 + (_pulseController.value * 25),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00FFA3).withOpacity(0.08 * (1 - _pulseController.value)),
                      border: Border.all(
                        color: const Color(0xFF00FFA3).withOpacity(0.4 * (1 - _pulseController.value)),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF161E2E),
                          border: Border.all(color: const Color(0xFF00FFA3), width: 2),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.3), blurRadius: 20),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.callerName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Controls
              if (widget.isIncoming && !_hasConnected)
                // Incoming Call Actions (Accept / Decline)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    FloatingActionButton(
                      heroTag: 'decline_call',
                      backgroundColor: Colors.redAccent,
                      onPressed: widget.onEndCall,
                      child: const Icon(Icons.call_end, color: Colors.white),
                    ),
                    FloatingActionButton(
                      heroTag: 'accept_call',
                      backgroundColor: const Color(0xFF00FFA3),
                      onPressed: _startCallTimer,
                      child: const Icon(Icons.call, color: Colors.black),
                    ),
                  ],
                )
              else
                // In-Call Minimal Actions (Mute, End, Speaker)
                LiquidGlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  borderRadius: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: _isMuted ? Colors.redAccent : Colors.white, size: 26),
                        onPressed: () => setState(() => _isMuted = !_isMuted),
                      ),
                      FloatingActionButton(
                        heroTag: 'end_call_active',
                        backgroundColor: Colors.redAccent,
                        elevation: 4,
                        onPressed: widget.onEndCall,
                        child: const Icon(Icons.call_end, color: Colors.white),
                      ),
                      IconButton(
                        icon: Icon(_isSpeaker ? Icons.volume_up : Icons.volume_down, color: _isSpeaker ? const Color(0xFF00FFA3) : Colors.white, size: 26),
                        onPressed: () => setState(() => _isSpeaker = !_isSpeaker),
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
