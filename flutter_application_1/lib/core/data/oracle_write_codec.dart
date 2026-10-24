import 'dart:typed_data';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
// Native SDK sentinel adapter, pinned and tested against interface 8.0.5.
// ignore: implementation_imports
import 'package:cloud_firestore_platform_interface/src/method_channel/method_channel_field_value.dart';
import 'oracle_codec.dart';

/// Explicit typed wire format; sentinel values cannot be confused with user maps.
class OracleWriteCodec {
  final OracleCodec values;
  OracleWriteCodec(this.values);

  Map<String, dynamic> encode(dynamic value) {
    if (value is FieldValuePlatform) {
      final delegate = FieldValuePlatform.getDelegate(value);
      if (delegate is! MethodChannelFieldValue) {
        throw UnsupportedError('Alan işlemi bu cihazda desteklenmiyor.');
      }
      final operation = switch (delegate.type) {
        FieldValueType.serverTimestamp => 'serverTimestamp',
        FieldValueType.delete => 'delete',
        FieldValueType.incrementInteger ||
        FieldValueType.incrementDouble => 'increment',
        FieldValueType.arrayUnion => 'arrayUnion',
        FieldValueType.arrayRemove => 'arrayRemove',
      };
      return {
        'transformValue': {
          'operation': operation,
          if (delegate.value != null) 'value': encode(delegate.value),
        },
      };
    }
    if (value is Map<String, dynamic>) {
      return {
        'mapValue': {'fields': fields(value)},
      };
    }
    if (value is Uint8List) return values.encode(value);
    if (value is Iterable) {
      return {
        'arrayValue': {'values': value.map(encode).toList()},
      };
    }
    return values.encode(value);
  }

  Map<String, dynamic> fields(Map<String, dynamic> data) =>
      data.map((key, value) => MapEntry(key, encode(value)));

  Map<String, dynamic> set(
    String path,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) => {
    'type': 'set',
    'path': path,
    'fields': fields(data),
    if (options?.merge != null) 'merge': options!.merge,
    if (options?.mergeFields != null)
      'mergeFields': options!.mergeFields!.map((p) => p.components).toList(),
  };

  Map<String, dynamic> update(String path, Map<FieldPath, dynamic> data) => {
    'type': 'update',
    'path': path,
    'fields': [
      for (final entry in data.entries)
        {'field': entry.key.components, 'value': encode(entry.value)},
    ],
  };
}
