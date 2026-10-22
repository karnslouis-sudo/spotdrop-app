import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/github_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(52.5200, 13.4050); // Default Fallback: Berlin
  List<Map<String, dynamic>> _spots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initLocationAndSpots();
  }

  Future<void> _initLocationAndSpots() async {
    setState(() => _isLoading = true);
    await _determinePosition();
    await _fetchSpots();
    setState(() => _isLoading = false);
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentPosition, 15.0);
      }
    } catch (_) {
      // Fallback bleibt bestehen
    }
  }

  Future<void> _fetchSpots() async {
    final spots = await GitHubService().fetchSpots();
    if (mounted) {
      setState(() => _spots = spots);
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
          title: const Text('Neuen Spot droppen', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Spot Name / Treffpunkt',
                  hintText: 'z.B. Treffpunkt Parkbank',
                  filled: true,
                  fillColor: Color(0xFF161E2E),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FFA3), foregroundColor: Colors.black),
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
                    await _fetchSpots();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('🎯 Spot "$title" auf GitHub Server gedroppt!')),
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              MarkerLayer(
                markers: [
                  // Eigener Standort
                  Marker(
                    point: _currentPosition,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FFA3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Color(0xFF00FFA3), blurRadius: 10)],
                      ),
                      child: const Center(
                        child: Icon(Icons.person, size: 16, color: Colors.black),
                      ),
                    ),
                  ),

                  // Spots aus dem GitHub Server
                  ..._spots.map((spot) {
                    final lat = (spot['lat'] as num?)?.toDouble() ?? 0.0;
                    final lng = (spot['lng'] as num?)?.toDouble() ?? 0.0;
                    final isGeo = spot['is_geofenced'] == true;

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('📍 Spot: ${spot['title']} von ${spot['created_by']}')),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isGeo ? Colors.amber : const Color(0xFF6366F1),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            isGeo ? Icons.lock : Icons.location_on,
                            size: 20,
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

          // Top Info
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1420).withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1E283C)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Spots auf Server: ${_spots.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
                    onPressed: _fetchSpots,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: _promptAddSpot,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Spot an aktuellem Ort droppen', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFA3),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
