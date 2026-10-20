import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pair/couple_service.dart';
import 'offline_location_map.dart';

const locationPrefix = 'NEURAL_LOCATION:';

class LocationShares {
  static const _channel = MethodChannel('app/location');

  static Future<void> send(
    BuildContext context, {
    String? chatId,
    String? coupleId,
    required Future<void> Function(String, DateTime?) onSend,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konumunu 1 saat paylaş?'),
        content: const Text(
          'Şu an bulunduğun konum yalnızca bu sohbetin katılımcılarıyla bir saat paylaşılır. Hareketlerin takip edilmez. İstediğin an paylaşımı durdurabilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Paylaş'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Map<String, dynamic>? point;
    try {
      point = await _channel
          .invokeMapMethod<String, dynamic>('current')
          .timeout(const Duration(seconds: 25));
    } catch (error) {
      await _channel.invokeMethod<void>('cancel').catchError((_) {});
      if (!context.mounted) return;
      final denied = error is PlatformException && error.code == 'denied';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? 'Konum izni verilmedi. Paylaşım yapılmadı.'
                : 'Konum alınamadı. Telefonun konum ayarını açıp yeniden dene.',
          ),
        ),
      );
      return;
    }
    if (point == null || !context.mounted) return;
    await CoupleService.ensureReady();
    final doc = FirebaseFirestore.instance.collection('sharedLocations').doc();
    await doc.set({
      'owner': CoupleService.uid,
      'chatId': chatId,
      'coupleId': coupleId,
      'latitude': point['latitude'],
      'longitude': point['longitude'],
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Store only a share ID and a time for eventual deletion, never coordinates.
    await (await SharedPreferences.getInstance()).setInt(
      'location_cleanup_${doc.id}',
      DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await onSend(locationPrefix + doc.id, null);
    } catch (_) {
      await remove(doc.id).catchError((_) {});
      rethrow;
    }
  }

  static Future<void> remove(String id) =>
      FirebaseFirestore.instance.collection('sharedLocations').doc(id).delete();

  static Future<void> cleanupExpired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('location_cleanup_'),
    )) {
      if ((prefs.getInt(key) ?? 0) > cutoff) continue;
      try {
        await remove(key.substring('location_cleanup_'.length));
        await prefs.remove(key);
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' || error.code == 'not-found') {
          await prefs.remove(key);
        }
      }
    }
  }
}

class LocationShareCard extends StatefulWidget {
  final String id;
  const LocationShareCard({super.key, required this.id});
  @override
  State<LocationShareCard> createState() => _LocationShareCardState();
}

class _LocationShareCardState extends State<LocationShareCard> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _stream;
  Timer? _expiry;
  bool _expired = false;
  DateTime? _deadline;
  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('sharedLocations')
        .doc(widget.id)
        .snapshots();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _stream,
    builder: (_, snapshot) {
      final data = snapshot.data?.data();
      if (_expired ||
          (snapshot.hasData && data == null) ||
          (snapshot.error is FirebaseException &&
              (snapshot.error as FirebaseException).code ==
                  'permission-denied')) {
        return const Text('📍 Konum paylaşımı sona erdi');
      }
      if (snapshot.hasError) {
        return const Text(
          '📍 Konum yüklenemedi. İnternet bağlantını kontrol et.',
        );
      }
      final created = data?['createdAt'];
      if (created is! Timestamp) return const Text('📍 Konum yükleniyor…');
      final expires = created.toDate().add(const Duration(hours: 1));
      if (!expires.isAfter(DateTime.now())) {
        return const Text('📍 Konum paylaşımı sona erdi');
      }
      if (_deadline != expires) {
        _deadline = expires;
        _expiry?.cancel();
        _expiry = Timer(expires.difference(DateTime.now()), () {
          if (mounted) setState(() => _expired = true);
          LocationShares.remove(widget.id).catchError((_) {});
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '📍 Anlık konum',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Haritada göster'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => Dialog(
                child: SizedBox(
                  width: 420,
                  height: 440,
                  child: Column(
                    children: [
                      AppBar(
                        title: const Text('Paylaşılan konum'),
                        automaticallyImplyLeading: false,
                        actions: [
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Expanded(
                        child: OfflineLocationMap(
                          latitude: (data!['latitude'] as num).toDouble(),
                          longitude: (data['longitude'] as num).toDouble(),
                          expiresAt: expires,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Text(
            'Bitiş: ${expires.hour.toString().padLeft(2, '0')}:${expires.minute.toString().padLeft(2, '0')}',
          ),
          if (data!['owner'] == CoupleService.uid)
            TextButton(
              onPressed: () async {
                try {
                  await LocationShares.remove(widget.id);
                  if (mounted) setState(() => _expired = true);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Paylaşım durdurulamadı. Yeniden dene.'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Paylaşımı durdur'),
            ),
        ],
      );
    },
  );
}
