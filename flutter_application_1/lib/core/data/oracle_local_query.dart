import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'oracle_codec.dart';
import 'oracle_local_values.dart';

const _missing = _Missing();

class _Missing {
  const _Missing();
}

int _compare(dynamic a, dynamic b) {
  if (a == b) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is Timestamp && b is Timestamp) return a.compareTo(b);
  if (a is num && b is num) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  if (a is DocumentReferencePlatform) a = a.path;
  if (b is DocumentReferencePlatform) b = b.path;
  if (a is String && b is String) {
    final left = a.runes.toList(), right = b.runes.toList();
    for (var i = 0; i < left.length && i < right.length; i++) {
      final result = left[i].compareTo(right[i]);
      if (result != 0) return result;
    }
    return left.length.compareTo(right.length);
  }
  return a.toString().compareTo(b.toString());
}

dynamic _field(Map row, List field, OracleCodec codec) {
  if (field.length == 1 && field[0] == '__name__') return row['path'];
  dynamic value = row['document']?['fields'];
  for (var i = 0; i < field.length; i++) {
    if (value is! Map || !value.containsKey(field[i])) return _missing;
    value = value[field[i]];
    if (i < field.length - 1) value = value['mapValue']?['fields'];
  }
  return codec.decode(value as Map);
}

bool _matches(Map row, Map query, OracleCodec codec) {
  final path = row['path'] as String;
  if (path.substring(0, path.lastIndexOf('/')) != query['path']) {
    return false;
  }
  for (final filter in query['filters'] as List? ?? []) {
    final value = _field(row, filter['field'] as List, codec);
    if (value is _Missing) return false;
    final expected = codec.decode(filter['value'] as Map);
    final okay = switch (filter['op']) {
      '==' => oracleValuesEqual(value, expected),
      '!=' => !oracleValuesEqual(value, expected),
      '<' => _compare(value, expected) < 0,
      '<=' => _compare(value, expected) <= 0,
      '>' => _compare(value, expected) > 0,
      '>=' => _compare(value, expected) >= 0,
      'in' => (expected as List).any((x) => oracleValuesEqual(value, x)),
      'not-in' => !(expected as List).any((x) => oracleValuesEqual(value, x)),
      'array-contains' =>
        value is List && value.any((x) => oracleValuesEqual(x, expected)),
      'array-contains-any' =>
        value is List &&
            value.any(
              (x) => (expected as List).any((v) => oracleValuesEqual(x, v)),
            ),
      _ => false,
    };
    if (!okay) return false;
  }
  return true;
}

List<Map<String, dynamic>> oracleLocalQuery(
  Iterable<Map<String, dynamic>> rows,
  Map<String, dynamic> query,
  OracleCodec codec,
) {
  final orders = <Map>[...List<Map>.from(query['orders'] as List? ?? [])];
  if (!orders.any((o) => oracleValuesEqual(o['field'], ['__name__']))) {
    orders.add({
      'field': ['__name__'],
      'descending': orders.lastOrNull?['descending'] ?? false,
    });
  }
  final result = rows
      .where(
        (row) =>
            _matches(row, query, codec) &&
            orders.every(
              (o) => _field(row, o['field'] as List, codec) is! _Missing,
            ),
      )
      .toList();
  result.sort((a, b) {
    for (final order in orders) {
      var value = _compare(
        _field(a, order['field'] as List, codec),
        _field(b, order['field'] as List, codec),
      );
      if (order['descending'] == true) value = -value;
      if (value != 0) return value;
    }
    return 0;
  });
  bool cursor(Map row, String key, bool end, bool inclusive) {
    final values = query[key] as List?;
    if (values == null) return true;
    for (var i = 0; i < values.length; i++) {
      var compared = _compare(
        _field(row, orders[i]['field'] as List, codec),
        codec.decode(values[i] as Map),
      );
      if (orders[i]['descending'] == true) compared = -compared;
      if (compared != 0) return end ? compared < 0 : compared > 0;
    }
    return inclusive;
  }

  final selected = result
      .where(
        (row) =>
            cursor(row, 'startAt', false, true) &&
            cursor(row, 'startAfter', false, false) &&
            cursor(row, 'endAt', true, true) &&
            cursor(row, 'endBefore', true, false),
      )
      .toList();
  final limit = query['limit'] as int?;
  if (limit == null || selected.length <= limit) return selected;
  return query['limitToLast'] == true
      ? selected.sublist(selected.length - limit)
      : selected.take(limit).toList();
}
