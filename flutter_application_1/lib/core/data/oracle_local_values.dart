import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'oracle_codec.dart';

const _deleted = _Deleted();

class _Deleted {
  const _Deleted();
}

bool oracleValuesEqual(dynamic a, dynamic b) {
  if (a is Blob && b is Blob) {
    return oracleValuesEqual(a.bytes.toList(), b.bytes.toList());
  }
  if (a is DocumentReferencePlatform && b is DocumentReferencePlatform) {
    return a.path == b.path;
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        [
          for (var i = 0; i < a.length; i++) oracleValuesEqual(a[i], b[i]),
        ].every((v) => v);
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && oracleValuesEqual(a[k], b[k]));
  }
  return a == b;
}

dynamic _resolve(Map value, dynamic old, OracleCodec codec, Timestamp clock) {
  final transform = value['transformValue'];
  if (transform is Map) {
    final step = transform.containsKey('value')
        ? codec.decode(transform['value'] as Map)
        : null;
    switch (transform['operation']) {
      case 'serverTimestamp':
        return clock;
      case 'delete':
        return _deleted;
      case 'increment':
        final initial = old is num ? old : 0;
        if (initial is int && step is int) {
          final n = BigInt.from(initial) + BigInt.from(step);
          final max = BigInt.parse('9223372036854775807'),
              min = BigInt.parse('-9223372036854775808');
          return (n > max
                  ? max
                  : n < min
                  ? min
                  : n)
              .toInt();
        }
        return initial + (step as num);
      case 'arrayUnion':
        final values = old is List ? [...old] : <dynamic>[];
        for (final v in step as List) {
          if (!values.any((x) => oracleValuesEqual(x, v))) values.add(v);
        }
        return values;
      case 'arrayRemove':
        return old is List
            ? old
                  .where(
                    (x) => !(step as List).any((v) => oracleValuesEqual(x, v)),
                  )
                  .toList()
            : <dynamic>[];
    }
  }
  if (value['mapValue'] is Map) {
    final fields = value['mapValue']['fields'] as Map? ?? {};
    final result = <String, dynamic>{};
    for (final entry in fields.entries) {
      final v = _resolve(
        entry.value as Map,
        old is Map ? old[entry.key] : null,
        codec,
        clock,
      );
      if (v is! _Deleted) result[entry.key as String] = v;
    }
    return result;
  }
  return codec.decode(value);
}

dynamic _at(Map? data, List<String> path) {
  dynamic value = data;
  for (final key in path) {
    value = value is Map ? value[key] : null;
  }
  return value;
}

void _put(Map<String, dynamic> data, List<String> path, dynamic value) {
  var target = data;
  for (final part in path.take(path.length - 1)) {
    if (target[part] is! Map<String, dynamic>) {
      target[part] = <String, dynamic>{};
    }
    target = target[part] as Map<String, dynamic>;
  }
  if (value is _Deleted) {
    target.remove(path.last);
  } else {
    target[path.last] = value;
  }
}

Map _rawAt(Map fields, List<String> path) {
  dynamic value = {
    'mapValue': {'fields': fields},
  };
  for (final part in path) {
    value = value['mapValue']['fields'][part];
  }
  return value as Map;
}

List<List<String>> _leaves(Map fields, [List<String> prefix = const []]) {
  final result = <List<String>>[];
  for (final entry in fields.entries) {
    final path = [...prefix, entry.key as String], value = entry.value as Map;
    final nested = value['mapValue']?['fields'] as Map?;
    if (nested != null && nested.isNotEmpty) {
      result.addAll(_leaves(nested, path));
    } else {
      result.add(path);
    }
  }
  return result;
}

/// Local estimates drive pending-write UI only; the server remains authoritative.
Map<String, dynamic>? applyOracleLocalWrite(
  Map<String, dynamic>? old,
  Map<String, dynamic> operation,
  OracleCodec codec,
  Timestamp clock,
) {
  if (operation['type'] == 'delete') return null;
  if (old != null) {
    old = codec.fields(old.map((k, v) => MapEntry(k, codec.encode(v))));
  }
  if (operation['type'] == 'update') {
    final result = Map<String, dynamic>.from(old ?? {});
    for (final field in operation['fields'] as List) {
      final path = List<String>.from(field['field'] as List);
      _put(
        result,
        path,
        _resolve(field['value'] as Map, _at(old, path), codec, clock),
      );
    }
    return result;
  }
  final fields = operation['fields'] as Map;
  final merge =
      operation['merge'] == true || operation.containsKey('mergeFields');
  final result = merge
      ? Map<String, dynamic>.from(old ?? {})
      : <String, dynamic>{};
  final mask = operation['mergeFields'] as List?;
  final paths = mask != null
      ? mask.map((p) => List<String>.from(p as List)).toList()
      : merge
      ? _leaves(fields)
      : fields.keys.map((k) => [k as String]).toList();
  for (final path in paths) {
    _put(
      result,
      path,
      _resolve(_rawAt(fields, path), _at(old, path), codec, clock),
    );
  }
  return result;
}
