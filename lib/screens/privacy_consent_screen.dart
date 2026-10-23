import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/glass_container.dart';

class PrivacyConsentScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  const PrivacyConsentScreen({super.key, required this.onAccepted});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _termsAccepted = false;
  bool _locationAccepted = false;

  Future<void> _submitConsent() async {
    if (!_termsAccepted || !_locationAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte akzeptiere die rechtlichen Bestimmungen, um fortzufahren.')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('spotdrop_legal_consent', true);
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06090E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF00FFA3)]),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.3), blurRadius: 18),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.security, color: Colors.black, size: 28),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Datenschutz & Rechtliches',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Transparenz & Sicherheit für deine privaten Crew-Daten.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
                const SizedBox(height: 24),

                LiquidGlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. DATENSCHUTZ (DSGVO)', style: TextStyle(color: Color(0xFF00FFA3), fontWeight: FontWeight.bold, fontSize: 11)),
                      const SizedBox(height: 6),
                      Text(
                        'Spotdrop speichert deine Daten (Chats, Fotos, Standorte) ausschließlich in dem von deiner Crew kontrollierten privaten GitHub-Repository. Es findet kein Tracking durch Werbenetzwerke statt.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade300, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      const Text('2. HINTERGRUND-STANDORT & NOTRUF', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold, fontSize: 11)),
                      const SizedBox(height: 6),
                      Text(
                        'Für die Unfallerkennung und die Live-Radar-Karte wird dein Standort auch im Hintergrund aktualisiert, wenn du dies aktivierst. Im Notfall wird deine Position an deine Crew gesendet.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade300, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Checkbox 1
                LiquidGlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: CheckboxListTile(
                    value: _termsAccepted,
                    activeColor: const Color(0xFF00FFA3),
                    checkColor: Colors.black,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ich stimme den Nutzungsbedingungen und AGB zu.', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    onChanged: (val) => setState(() => _termsAccepted = val ?? false),
                  ),
                ),
                const SizedBox(height: 10),

                // Checkbox 2
                LiquidGlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: CheckboxListTile(
                    value: _locationAccepted,
                    activeColor: const Color(0xFF00FFA3),
                    checkColor: Colors.black,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ich akzeptiere die GPS- und Notfallerkennungs-Klausel.', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    onChanged: (val) => setState(() => _locationAccepted = val ?? false),
                  ),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFA3),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: _submitConsent,
                  child: const Text('Zustimmen & App starten', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
