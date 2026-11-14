import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Null if storage is unavailable; preferences are a convenience, never fatal.
Future<SharedPreferences?> prefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null;
  }
}

/// A notifier whose state survives restarts. It starts at [defaults], applies
/// the stored value once loaded, and writes every [put]. A [put] made before
/// the load finishes wins over the stored value.
abstract class PersistedNotifier<T> extends Notifier<T> {
  T get defaults;

  /// The stored value, or null if there is none or it is unusable.
  T? read(SharedPreferences p);

  Future<void> write(SharedPreferences p, T value);

  bool _touched = false;
  bool _disposed = false;

  @override
  T build() {
    ref.onDispose(() => _disposed = true);
    prefs().then((p) {
      if (p == null || _touched || _disposed) return;
      final stored = read(p);
      if (stored != null) state = stored;
    });
    return defaults;
  }

  void put(T value) {
    _touched = true;
    state = value;
    prefs().then((p) => p == null ? null : write(p, value));
  }
}
