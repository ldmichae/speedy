import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dashboard_layout.dart';
import '../core/prefs.dart';

final dashboardLayoutProvider =
    NotifierProvider<DashboardLayoutController, DashboardLayout>(
        DashboardLayoutController.new);

class DashboardLayoutController extends PersistedNotifier<DashboardLayout> {
  static const _key = 'dashboardLayout';

  @override
  DashboardLayout get defaults => DashboardLayout.standard;

  @override
  DashboardLayout? read(SharedPreferences p) =>
      DashboardLayout.fromJson(p.getString(_key));

  @override
  Future<void> write(SharedPreferences p, DashboardLayout v) =>
      p.setString(_key, v.toJson());

  void moveTo(TileKind kind, Side side, int index) =>
      put(state.moveTo(kind, side, index));
  void resize(TileKind k, {int? span, int? rows}) =>
      put(state.resize(k, span: span, rows: rows));
  void showInstead(TileKind current, TileKind other) =>
      put(state.showInstead(current, other));
  void remove(TileKind k) => put(state.remove(k));
  void add(TileKind k) => put(state.add(k));
  void reset() => put(DashboardLayout.standard);
}
