import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  Color _accentColor = const Color(0xFF00FFA3);
  String _glassStyle = 'liquid'; // 'liquid', 'obsidian', 'neon'

  Color get accentColor => _accentColor;
  String get glassStyle => _glassStyle;

  static const List<Map<String, dynamic>> availableColors = [
    {'name': 'Neon Mint', 'color': Color(0xFF00FFA3)},
    {'name': 'Cyber Purple', 'color': Color(0xFF8B5CF6)},
    {'name': 'Electric Cyan', 'color': Color(0xFF06B6D4)},
    {'name': 'Sunset Pink', 'color': Color(0xFFEC4899)},
    {'name': 'Solar Gold', 'color': Color(0xFFF59E0B)},
    {'name': 'Crimson Red', 'color': Color(0xFFFF4757)},
  ];

  static const List<Map<String, String>> availableStyles = [
    {'id': 'liquid', 'name': 'Liquid Glass (VisionOS)', 'desc': 'Klassischer Frosted Blur mit Lichtkanten'},
    {'id': 'obsidian', 'name': 'Deep Obsidian (OLED)', 'desc': 'Tiefschwarzes Glas für OLED-Displays'},
    {'id': 'neon', 'name': 'Cyberpunk Matrix', 'desc': 'Starker Neon-Rahmen mit dunklem Kern'},
  ];

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final colorVal = prefs.getInt('spotdrop_accent_color');
    if (colorVal != null) {
      _accentColor = Color(colorVal);
    }
    _glassStyle = prefs.getString('spotdrop_glass_style') ?? 'liquid';
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('spotdrop_accent_color', color.value);
    notifyListeners();
  }

  Future<void> setGlassStyle(String style) async {
    _glassStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spotdrop_glass_style', style);
    notifyListeners();
  }
}
