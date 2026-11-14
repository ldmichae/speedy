import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ride_history_store.dart';
import '../core/ride_record.dart';

final rideHistoryStoreProvider =
    Provider<RideHistoryStore>((ref) => createRideHistoryStore());

/// Saved rides, newest first. Unreadable records are skipped rather than
/// hiding the whole history.
final rideHistoryProvider = FutureProvider<List<RideRecord>>((ref) async {
  final raw = await ref.watch(rideHistoryStoreProvider).loadAll();
  final rides = <RideRecord>[];
  for (final json in raw) {
    try {
      rides.add(RideRecord.fromJson(jsonDecode(json) as Map<String, Object?>));
    } catch (_) {}
  }
  rides.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return rides;
});
