import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'navigation.dart';
import 'recorder_controller.dart';
import 'ride_session.dart';
import 'trainer_controller.dart';

/// What the rider can do on the ride screen without touching it. The keyboard
/// uses it today; any other control can too.
class RideCommands {
  RideCommands(this._ref);
  final Ref _ref;

  /// The dashboard stays alive behind the other pages in the dock, so its
  /// keys must not act while one of them is open.
  bool get onRidePage => _ref.read(pageProvider) == AppPage.ride;

  /// Records, pauses or resumes.
  void toggleRecording() => _ref.read(recorderProvider.notifier).toggle();

  /// Moves the ERG target by [watts], unless a plan or simulation owns it.
  void nudgeTarget(int watts) {
    if (_ref.read(targetLockProvider) == null) {
      _ref.read(trainerControllerProvider.notifier).adjustTarget(watts);
    }
  }

  /// Shifts the virtual gear by [gears]; does nothing outside SIM mode.
  void shift(int gears) =>
      _ref.read(trainerControllerProvider.notifier).shift(gears);

  /// The arrow keys: one gear while a route sets the resistance (the target
  /// is locked then anyway), otherwise the ERG target by [watts].
  void nudge(int watts) =>
      _ref.read(targetLockProvider) == TargetLock.simulation
          ? shift(watts.sign)
          : nudgeTarget(watts);
}

final rideCommandsProvider = Provider(RideCommands.new);

/// Space records, pauses or resumes; the arrow keys move the target by 5 W
/// (25 W with Shift), or shift one gear on a simulated route. [onTop] says
/// whether the screen is the one on top, not under a dialog or a pushed screen.
Map<ShortcutActivator, VoidCallback> rideShortcuts(
    RideCommands c, bool Function() onTop) {
  VoidCallback guarded(VoidCallback f) => () {
        if (onTop() && c.onRidePage) f();
      };
  return {
    const SingleActivator(LogicalKeyboardKey.space):
        guarded(c.toggleRecording),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        guarded(() => c.nudge(5)),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        guarded(() => c.nudge(-5)),
    const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
        guarded(() => c.nudge(25)),
    const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
        guarded(() => c.nudge(-25)),
  };
}
