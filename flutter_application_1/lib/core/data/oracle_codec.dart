import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

/// Preserve typed encrypted bytes, timestamps and int64 values across the API.
class OracleCodec {
  final DocumentReferencePlatform Function(String) reference;
  final String project;
  OracleCodec({required this.reference, required this.project});
  dynamic decode(Map value) {
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) {
      return int.parse(value['integerValue'].toString());
    }
    if (value.containsKey('doubleValue')) {
      final n = value['doubleValue'];
      return n is num ? n.toDouble() : double.parse(n as String);
    }
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('bytesValue')) {
      return Blob(base64Decode(value['bytesValue'] as String));
    }
    if (value.containsKey('timestampValue')) {
      final match = RegExp(
        r'^(.+?)(?:\.(\d{1,9}))?Z$',
      ).firstMatch(value['timestampValue'] as String);
      if (match == null) throw const FormatException('Tarih biçimi geçersiz.');
      return Timestamp(
        DateTime.parse('${match[1] ?? ''}Z').millisecondsSinceEpoch ~/ 1000,
        int.parse((match[2] ?? '').padRight(9, '0')),
      );
    }
    if (value.containsKey('geoPointValue')) {
      final g = value['geoPointValue'] as Map;
      return GeoPoint(
        (g['latitude'] as num).toDouble(),
        (g['longitude'] as num).toDouble(),
      );
    }
    if (value.containsKey('referenceValue')) {
      final prefix = 'projects/$project/databases/(default)/documents/';
      final text = value['referenceValue'] as String;
      if (!text.startsWith(prefix)) {
        throw const FormatException('Kayıt yolu geçersiz.');
      }
      return reference(text.substring(prefix.length));
    }
    if (value.containsKey('arrayValue')) {
      return [
        for (final item in (value['arrayValue']['values'] as List? ?? []))
          decode(item as Map),
      ];
    }
    if (value.containsKey('mapValue')) {
      return fields(value['mapValue']['fields'] as Map? ?? {});
    }
    throw UnsupportedError('Desteklenmeyen veri türü.');
  }

  Map<String, dynamic> fields(Map input) => {
    for (final entry in input.entries)
      entry.key as String: decode(entry.value as Map),
  };
  Map<String, dynamic> encode(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is String) return {'stringValue': value};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is double && value.isFinite) return {'doubleValue': value};
    if (value is DateTime) return encode(Timestamp.fromDate(value));
    if (value is Timestamp) {
      final base = DateTime.fromMillisecondsSinceEpoch(
        value.seconds * 1000,
        isUtc: true,
      ).toIso8601String().split('.').first;
      final nanos = value.nanoseconds.toString().padLeft(9, '0');
      return {'timestampValue': '$base.${nanos}Z'};
    }
    if (value is Blob) return {'bytesValue': base64Encode(value.bytes)};
    if (value is Uint8List) return {'bytesValue': base64Encode(value)};
    if (value is DocumentReferencePlatform) {
      return {
        'referenceValue':
            'projects/$project/databases/(default)/documents/${value.path}',
      };
    }
    if (value is GeoPoint) {
      return {
        'geoPointValue': {
          'latitude': value.latitude,
          'longitude': value.longitude,
        },
      };
    }
    if (value is Iterable) {
      return {
        'arrayValue': {'values': value.map(encode).toList()},
      };
    }
    if (value is Map<String, dynamic>) {
      return {
        'mapValue': {'fields': value.map((k, v) => MapEntry(k, encode(v)))},
      };
    }
    throw UnsupportedError('Desteklenmeyen filtre değeri.');
  }
}
