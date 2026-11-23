import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';

/// The places the left dock leads to.
enum AppPage {
  ride('Ride', Icons.directions_bike_outlined, Icons.directions_bike),
  devices('Devices', Icons.bluetooth, Icons.bluetooth_connected),
  routes('Routes', Icons.map_outlined, Icons.map),
  tours('Tours', Icons.hiking, Icons.hiking),
  compete('Compete', Icons.emoji_events_outlined, Icons.emoji_events),
  plans('Plans', Icons.list_alt_outlined, Icons.list_alt),
  history('History', Icons.history, Icons.history),
  preferences('Preferences', Icons.settings_outlined, Icons.settings);

  const AppPage(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The page showing in the main area. Starting a ride from Routes, Plans or
/// Tours sets this back to [AppPage.ride].
final pageProvider = StateProvider<AppPage>((ref) => AppPage.ride);

/// Whether the dock shows labels (true) or only icons (false). Remembered.
final dockExpandedProvider =
    NotifierProvider<DockExpandedController, bool>(DockExpandedController.new);

class DockExpandedController extends PersistedNotifier<bool> {
  static const _key = 'dockExpanded';

  @override
  bool get defaults => true;

  @override
  bool? read(SharedPreferences p) => p.getBool(_key);

  @override
  Future<void> write(SharedPreferences p, bool v) => p.setBool(_key, v);

  void toggle() => put(!state);
}
