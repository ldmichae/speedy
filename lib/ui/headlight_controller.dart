import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';

/// Whether your bike's headlight is on in the World view. Remembered between
/// rides.
final headlightProvider =
    NotifierProvider<HeadlightController, bool>(HeadlightController.new);

class HeadlightController extends PersistedNotifier<bool> {
  static const _key = 'headlight';

  @override
  bool get defaults => false;

  @override
  bool? read(SharedPreferences p) => p.getBool(_key);

  @override
  Future<void> write(SharedPreferences p, bool v) => p.setBool(_key, v);

  void toggle() => put(!state);
}
