import 'dart:collection';

/// Rolling average of power over a time window (default 3 s).
/// Time is passed in so this stays deterministic and unit-testable.
class PowerSmoother {
  PowerSmoother({this.window = const Duration(seconds: 3)});

  final Duration window;
  final Queue<(Duration, int)> _samples = Queue();

  double add(int watts, Duration at) {
    _samples.addLast((at, watts));
    while (_samples.isNotEmpty && at - _samples.first.$1 > window) {
      _samples.removeFirst();
    }
    final sum = _samples.fold<int>(0, (a, s) => a + s.$2);
    return sum / _samples.length;
  }

  void reset() => _samples.clear();
}
