import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';
import '../core/rider_profile.dart';

final riderProfileProvider =
    NotifierProvider<RiderProfileController, RiderProfile>(
        RiderProfileController.new);

class RiderProfileController extends PersistedNotifier<RiderProfile> {
  static const _height = 'riderHeightCm';
  static const _weight = 'riderWeightKg';
  static const _age = 'riderAge';
  static const _sex = 'riderSex';

  @override
  RiderProfile get defaults => const RiderProfile();

  @override
  RiderProfile? read(SharedPreferences p) {
    if (![_height, _weight, _age, _sex].any(p.containsKey)) return null;
    final sex = p.getString(_sex);
    return RiderProfile(
      heightCm: p.getInt(_height),
      weightKg: p.getDouble(_weight),
      age: p.getInt(_age),
      sex: Sex.values.where((s) => s.name == sex).firstOrNull,
    );
  }

  @override
  Future<void> write(SharedPreferences p, RiderProfile v) async {
    Future<void> set<T>(String key, T? value, Future<bool> Function(T) save) =>
        value == null ? p.remove(key) : save(value);
    await set(_height, v.heightCm, (x) => p.setInt(_height, x));
    await set(_weight, v.weightKg, (x) => p.setDouble(_weight, x));
    await set(_age, v.age, (x) => p.setInt(_age, x));
    await set(_sex, v.sex?.name, (x) => p.setString(_sex, x));
  }

  void update(RiderProfile profile) => put(profile);
}
