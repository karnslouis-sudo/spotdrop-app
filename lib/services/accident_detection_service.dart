import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'github_service.dart';

typedef EmergencyCallback = void Function(int secondsRemaining);

class AccidentDetectionService {
  static final AccidentDetectionService _instance = AccidentDetectionService._internal();
  factory AccidentDetectionService() => _instance;
  AccidentDetectionService._internal();

  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  bool _isMonitoring = false;
  bool _isEmergencyActive = false;
  Timer? _countdownTimer;
  int _secondsLeft = 30;

  bool get isMonitoring => _isMonitoring;
  bool get isEmergencyActive => _isEmergencyActive;

  /// Startet die präzise G-Kraft Überwachung
  void startMonitoring({required Function() onCrashDetected, required EmergencyCallback onTick}) {
    if (_isMonitoring) return;
    _isMonitoring = true;

    try {
      _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
        // Gesamte Beschleunigung berechnen: a = sqrt(x^2 + y^2 + z^2)
        final double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

        // Crash Threshold: >= 32.0 m/s^2 (entspricht ca. 3.2G plötzlichem Aufprall)
        if (magnitude >= 32.0 && !_isEmergencyActive) {
          _triggerCrashCountdown(onCrashDetected, onTick);
        }
      });
    } catch (_) {
      // Sensoren nicht verfügbar (z.B. Emulator)
    }
  }

  void _triggerCrashCountdown(Function() onCrashDetected, EmergencyCallback onTick) {
    _isEmergencyActive = true;
    _secondsLeft = 30;
    onCrashDetected();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _secondsLeft--;
      onTick(_secondsLeft);

      if (_secondsLeft <= 0) {
        timer.cancel();
        await _sendEmergencySOS();
      }
    });
  }

  /// Manuelles Auslösen zum Testen oder bei manuellem Notruf
  void testTriggerEmergency(Function() onCrashDetected, EmergencyCallback onTick) {
    if (!_isEmergencyActive) {
      _triggerCrashCountdown(onCrashDetected, onTick);
    }
  }

  /// Nutzer bricht Alarm ab (Fehlalarm)
  void cancelEmergency() {
    _isEmergencyActive = false;
    _countdownTimer?.cancel();
  }

  /// Sendet automatischen SOS-Notruf an die gesamte Gruppe
  Future<void> _sendEmergencySOS() async {
    _isEmergencyActive = false;
    _countdownTimer?.cancel();

    double lat = 52.5200;
    double lng = 13.4050;
    try {
      final pos = await Geolocator.getCurrentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    final service = GitHubService();
    await service.broadcastEmergencyAlert(lat: lat, lng: lng);
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _accelSubscription?.cancel();
    _countdownTimer?.cancel();
  }
}
