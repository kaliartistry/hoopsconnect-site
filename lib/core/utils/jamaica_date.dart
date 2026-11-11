import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

DateTime jamaicaCalendarTime(DateTime instant) =>
    instant.toUtc().subtract(const Duration(hours: 5));

String jamaicaDateKey(DateTime instant) =>
    jamaicaCalendarTime(instant).toIso8601String().substring(0, 10);

String? calendarDateKey(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final date = DateTime.tryParse('${value}T00:00:00Z');
  return date?.toIso8601String().substring(0, 10) == value ? value : null;
}

final jamaicaDateProvider = Provider.autoDispose<String>((ref) {
  final now = DateTime.now();
  final local = jamaicaCalendarTime(now);
  final midnight = DateTime.utc(local.year, local.month, local.day + 1);
  final timer = Timer(midnight.difference(local), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return jamaicaDateKey(now);
});
