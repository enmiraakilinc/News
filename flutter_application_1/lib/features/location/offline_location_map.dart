import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class OfflineLocationMap extends StatefulWidget {
  final double latitude;
  final double longitude;
  final DateTime expiresAt;
  const OfflineLocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.expiresAt,
  });
  @override
  State<OfflineLocationMap> createState() => _OfflineLocationMapState();
}

class _OfflineLocationMapState extends State<OfflineLocationMap> {
  static final Future<Map<String, dynamic>> _data = rootBundle
      .loadString('assets/maps/world.json')
      .then((text) => jsonDecode(text) as Map<String, dynamic>);
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    final remaining = widget.expiresAt.difference(DateTime.now());
    _timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.expiresAt.isAfter(DateTime.now())) {
      return const Center(child: Text('Konum paylaşımı sona erdi'));
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (_, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Çevrimdışı harita • Sokak ayrıntısı yok',
                style: TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(widget.latitude, widget.longitude),
                  initialZoom: 5,
                  minZoom: 2,
                  maxZoom: 12,
                  backgroundColor: const Color(0xffc3e0ee),
                ),
                children: [
                  PolygonLayer(
                    polygons: [
                      for (final ring in data['polygons'] as List)
                        Polygon(
                          points: [
                            for (final point in ring as List)
                              LatLng(
                                (point[1] as num).toDouble(),
                                (point[0] as num).toDouble(),
                              ),
                          ],
                          color: const Color(0xffe4e9d9),
                          borderColor: const Color(0xff929d87),
                          borderStrokeWidth: 1,
                        ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      for (final city in data['cities'] as List)
                        Marker(
                          point: LatLng(
                            (city['point'][1] as num).toDouble(),
                            (city['point'][0] as num).toDouble(),
                          ),
                          width: 100,
                          height: 22,
                          child: Text(
                            city['name'] as String,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      Marker(
                        point: LatLng(widget.latitude, widget.longitude),
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 48,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Text(
              'Harita: Natural Earth · Konum dış servise gönderilmez',
              style: TextStyle(fontSize: 10),
            ),
          ],
        );
      },
    );
  }
}
