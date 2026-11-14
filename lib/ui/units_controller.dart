import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';
import '../core/units.dart';

/// Units for ride data: speed and distance.
final rideUnitsProvider =
    NotifierProvider<RideUnitsController, UnitSystem>(RideUnitsController.new);

/// Units for body measurements: height and weight.
final bodyUnitsProvider =
    NotifierProvider<BodyUnitsController, UnitSystem>(BodyUnitsController.new);

abstract class _UnitsController extends PersistedNotifier<UnitSystem> {
  String get key;

  @override
  UnitSystem get defaults => UnitSystem.metric;

  @override
  UnitSystem? read(SharedPreferences p) {
    final name = p.getString(key);
    return UnitSystem.values.where((u) => u.name == name).firstOrNull;
  }

  @override
  Future<void> write(SharedPreferences p, UnitSystem u) =>
      p.setString(key, u.name);

  void set(UnitSystem u) => put(u);
}

class RideUnitsController extends _UnitsController {
  @override
  String get key => 'rideUnits';
}

class BodyUnitsController extends _UnitsController {
  @override
  String get key => 'bodyUnits';
}
