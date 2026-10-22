import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import '../services/github_service.dart';
import '../widgets/glass_container.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final Battery _battery = Battery();
  
  LatLng _currentPosition = const LatLng(52.5200, 13.4050); // Fallback Berlin
  int _batteryLevel = 100;
  List<Map<String, dynamic>> _spots = [];
  List<Map<String, dynamic>> _memberLocations = [];
  bool _isLoading = true;
  Timer? _locationSyncTimer;

  @override
  void initState() {
    super.initState();
    _initMapData();
    // Alle 10 Sekunden eigenen Standort & Akku synchronisieren und andere Crew-Mitglieder laden
    _locationSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) => _syncPresence(silent: true));
  }

  @override
  void dispose() {
    _locationSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _initMapData() async {
    setState(() => _isLoading = true);
    await _determinePositionAndBattery();
    await _syncPresence(silent: false);
    setState(() => _isLoading = false);
  }

  Future<void> _determinePositionAndBattery() async {
    try {
      // 1. Akku auslesen
      try {
        _batteryLevel = await _battery.batteryLevel;
      } catch (_) {
        _batteryLevel = 85; // Fallback
      }

      // 2. GPS auslesen
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(pos.latitude, pos.longitude);
        });
        _mapController.move(_currentPosition, 14.5);
      }
    } catch (_) {}
  }

  Future<void> _syncPresence({bool silent = false}) async {
    final service = GitHubService();
    if (service.currentGroup == null) return;

    // Eigene Position & Akku hochladen
    await service.updateLocationAndBattery(
      lat: _currentPosition.latitude,
      lng: _currentPosition.longitude,
      batteryLevel: _batteryLevel,
    );

    // Andere Mitglieder & Spots laden
    final members = await service.fetchMemberLocations();
    final spots = await service.fetchSpots();

    if (mounted) {
      setState(() {
        _memberLocations = members;
        _spots = spots;
      });
    }
  }

  Future<void> _promptAddSpot() async {
    final titleController = TextEditingController();
    bool isGeofenced = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF121722),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: Colors.white.withOpacity(0.12))),
          title: const Row(
            children: [
              Icon(Icons.add_location_alt, color: Color(0xFF00FFA3)),
              SizedBox(width: 8),
              Text('Neuen Spot droppen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Spot Name / Treffpunkt',
                  hintText: 'z.B. Treffpunkt Parkbank',
                  filled: true,
                  fillColor: const Color(0xFF161E2E),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Geofenced Drop (Geheim)', style: TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: const Text('Erst im Radius vor Ort freischaltbar', style: TextStyle(color: Colors.grey, fontSize: 11)),
                value: isGeofenced,
                activeColor: const Color(0xFF00FFA3),
                onChanged: (val) => setDialogState(() => isGeofenced = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFA3), 
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  Navigator.pop(ctx);
                  final success = await GitHubService().createSpot(
                    title: title,
                    lat: _currentPosition.latitude,
                    lng: _currentPosition.longitude,
                    isGeofenced: isGeofenced,
                  );
                  if (success) {
                    await _syncPresence(silent: true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF00FFA3),
                        content: Text('🎯 Spot "$title" auf der Map platziert!', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    );
                  }
                }
              },
              child: const Text('Droppen'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = GitHubService();
    final myName = service.userName;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: Stack(
        children: [
          // 100% KUGELSICHERE & STABILE DARK-MATTER MAP (KEIN WEISSER BILDSCHIRM!)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 14.5,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.spotdrop.app',
                maxZoom: 19,
                retinaMode: true,
              ),
              MarkerLayer(
                markers: [
                  // 1. EIGENER STANDORT MIT AKKU-PILL
                  Marker(
                    point: _currentPosition,
                    width: 70,
                    height: 65,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF00FFA3), width: 1),
                          ),
                          child: Text(
                            'Du (${_batteryLevel}%)',
                            style: const TextStyle(color: Color(0xFF00FFA3), fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FFA3),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF00FFA3).withOpacity(0.6), blurRadius: 12, spreadRadius: 2),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.person, size: 14, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. STANDORTE DER ANDEREN MITGLIEDER (LIVE TRACKING + AKKU)
                  ..._memberLocations.where((m) => m['user'] != myName).map((member) {
                    final lat = (member['lat'] as num?)?.toDouble() ?? 0.0;
                    final lng = (member['lng'] as num?)?.toDouble() ?? 0.0;
                    final battery = (member['battery'] as num?)?.toInt() ?? 100;
                    final isLowBattery = battery <= 5;
                    final name = member['user'] ?? 'Crew';

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 80,
                      height: 70,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('👤 $name • Akku: $battery% • Vor Kurzem aktiv')),
                          );
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isLowBattery ? Colors.red.shade900 : Colors.black.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isLowBattery ? Colors.redAccent : const Color(0xFF6366F1), 
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isLowBattery)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 2),
                                      child: Icon(Icons.warning_amber_rounded, size: 10, color: Colors.yellowAccent),
                                    ),
                                  Text(
                                    '$name ($battery%)',
                                    style: TextStyle(
                                      color: isLowBattery ? Colors.white : Colors.white70,
                                      fontSize: 9, 
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isLowBattery ? Colors.redAccent : const Color(0xFF6366F1),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isLowBattery ? Colors.redAccent : const Color(0xFF6366F1)).withOpacity(0.5), 
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  name.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // 3. SPOTS & DROPS DER GRUPPE
                  ..._spots.map((spot) {
                    final lat = (spot['lat'] as num?)?.toDouble() ?? 0.0;
                    final lng = (spot['lng'] as num?)?.toDouble() ?? 0.0;
                    final isGeo = spot['is_geofenced'] == true;

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 42,
                      height: 42,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('📍 Spot: ${spot['title']} (von ${spot['created_by']})')),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isGeo ? Colors.amber : const Color(0xFF00FFA3),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: (isGeo ? Colors.amber : const Color(0xFF00FFA3)).withOpacity(0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            isGeo ? Icons.lock : Icons.location_on,
                            size: 22,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // TOP LIQUID GLASS PILL
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              borderRadius: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00FFA3),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service.currentGroupName ?? 'Crew-Map',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            '${_memberLocations.length} Personen live • ${_spots.length} Spots',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.my_location, color: Color(0xFF00FFA3), size: 18),
                        onPressed: () => _mapController.move(_currentPosition, 15.5),
                        tooltip: 'Mein Standort',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                        onPressed: () => _syncPresence(silent: false),
                        tooltip: 'Neu laden',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // BOTTOM LIQUID GLASS ACTION BUTTON
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: GlassContainer(
              borderRadius: 26,
              padding: const EdgeInsets.all(4),
              child: ElevatedButton.icon(
                onPressed: _promptAddSpot,
                icon: const Icon(Icons.add_location_alt, color: Colors.black),
                label: const Text(
                  'Spot an meinem Ort droppen',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FFA3),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
