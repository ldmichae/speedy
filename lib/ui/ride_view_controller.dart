import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';

/// How the ride screen is arranged: the tile dashboard, or a map, chart or
/// 3D world (the course as a road) with the metrics grid below.
enum RideView {
  dashboard('Dashboard'),
  map('Map'),
  chart('Chart'),
  world('World');

  const RideView(this.label);
  final String label;
}

final rideViewProvider =
    NotifierProvider<RideViewController, RideView>(RideViewController.new);

class RideViewController extends PersistedNotifier<RideView> {
  @override
  RideView get defaults => RideView.dashboard;

  @override
  RideView? read(SharedPreferences p) {
    final name = p.getString('rideView');
    return RideView.values.where((v) => v.name == name).firstOrNull;
  }

  @override
  Future<void> write(SharedPreferences p, RideView v) =>
      p.setString('rideView', v.name);

  void set(RideView v) => put(v);
}
