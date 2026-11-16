import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/course.dart';
import '../core/ghost.dart';
import '../core/json_store.dart';
import '../core/ride_recording.dart';
import '../devices/trainer.dart';
import 'format.dart';
import 'recorder_controller.dart';
import 'ride_session.dart';
import 'rider_profile_controller.dart';
import 'route_controller.dart';
import 'trainer_controller.dart';

/// Overridable so tests do not touch the filesystem.
final ghostStoreProvider =
    Provider<JsonStore>((ref) => createJsonStore('ghosts'));

final ghostsProvider =
    AsyncNotifierProvider<GhostsController, List<Ghost>>(GhostsController.new);

/// Every stored ghost: your best and latest per course, and imported ones.
class GhostsController extends AsyncNotifier<List<Ghost>> {
  @override
  Future<List<Ghost>> build() async {
    final raw = await ref.read(ghostStoreProvider).loadAll();
    return [
      for (final s in raw)
        if (_decode(s) case final g?) g // an unreadable file hides only itself
    ];
  }

  static Ghost? _decode(String s) {
    try {
      return Ghost.fromJson(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }

  List<Ghost> get _all => state.valueOrNull ?? const [];

  /// Throws if the store cannot write.
  Future<void> save(Ghost g) async {
    await ref.read(ghostStoreProvider).save(g.id, jsonEncode(g.toJson()));
    state = AsyncData([..._all.where((x) => x.id != g.id), g]);
  }

  Future<void> delete(String id) async {
    await ref.read(ghostStoreProvider).delete(id);
    state = AsyncData([..._all.where((x) => x.id != id)]);
  }

  /// Saves a ride of yours, keeping only it and your best on that course.
  Future<void> addMine(Ghost g) async {
    await save(g);
    final best = bestOf(_all, g.course);
    for (final x in [..._all]) {
      if (x.mine && x.course == g.course && x.id != g.id && x.id != best?.id) {
        await delete(x.id);
      }
    }
  }

  /// Adds a ghost file someone sent. Throws [FormatException] with a message
  /// for the rider if it is not one this app can race.
  Future<Ghost> import(String text) async {
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      json = null;
    }
    final g = Ghost.fromJson(json);
    if (g == null) throw const FormatException('That is not a ghost file.');
    final c = courseById(g.course);
    if (c == null) {
      throw const FormatException(
          'That ghost is for a course this version of the app does not have.');
    }
    // A ghost that stops short (or overshoots) would not be a fair race.
    if ((g.meters - c.route.lengthMeters).abs() > 5) {
      throw const FormatException('That ghost does not finish the course.');
    }
    final imported = g.named(g.name); // never "mine", whatever the file says
    await save(imported);
    return imported;
  }
}

/// Your fastest ride of [course] among [all], if any.
Ghost? bestOf(List<Ghost> all, String course) {
  Ghost? best;
  for (final g in all) {
    if (g.mine && g.course == course && (best == null || g.seconds < best.seconds)) {
      best = g;
    }
  }
  return best;
}

/// How a ghost is listed: yours by role, others by the name they gave.
String ghostLabel(Ghost g, List<Ghost> all) => !g.mine
    ? g.name
    : bestOf(all, g.course)?.id == g.id
        ? 'Your best'
        : 'Your last ride';

/// A course lined up to race. It is staged first (warm up as you like, the
/// ride is not touched), then counts down, then is raced: [t0] is when the
/// start line was crossed on the recording's clock and [trace] the effort
/// so far. [result] is set at the finish.
class CompeteRun {
  CompeteRun(this.course, this.rivals,
      {this.countdown, this.t0 = 0, this.trace, this.result});
  final Course course;
  final List<Ghost> rivals;

  /// Seconds left before the start, while counting down.
  final int? countdown;
  final double t0;
  final GhostTrace? trace;
  final Ghost? result;

  bool get started => trace != null;
}

final competeProvider =
    NotifierProvider<CompeteController, CompeteRun?>(CompeteController.new);

class CompeteController extends Notifier<CompeteRun?> {
  static const countdownSeconds = 5;
  Timer? _timer;

  @override
  CompeteRun? build() {
    ref.onDispose(() => _timer?.cancel());
    // Once racing, stopping the route or riding something else ends it.
    ref.listen(routeRunProvider, (_, r) {
      final run = state;
      if (run != null && run.started && !identical(r?.course, run.course.route)) {
        state = null;
      }
    });
    ref.listen(recorderProvider, (_, __) => _tick());
    return null;
  }

  /// Lines up [c] against [rivals] without starting anything, so the rider
  /// can warm up first. Replaces any race already lined up or running.
  void stage(Course c, List<Ghost> rivals) {
    cancel();
    state = CompeteRun(c, rivals);
  }

  /// Counts down from [countdownSeconds], then starts the race.
  void startCountdown() {
    final run = state;
    if (run == null || run.started || run.countdown != null) return;
    state = CompeteRun(run.course, run.rivals, countdown: countdownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = state;
      if (r == null || r.countdown == null) return _timer?.cancel();
      if (r.countdown! > 1) {
        state = CompeteRun(r.course, r.rivals, countdown: r.countdown! - 1);
      } else {
        _timer?.cancel();
        _go(r);
      }
    });
  }

  /// Off the start line: starts (or resumes) recording and rides the course
  /// with simulated grades. Without a trainer it goes back to waiting.
  void _go(CompeteRun r) {
    if (ref.read(trainerControllerProvider).status != TrainerStatus.connected) {
      state = CompeteRun(r.course, r.rivals);
      return;
    }
    ref.read(rideSessionProvider.notifier).startRoute(r.course.route, simulate: true);
    state = CompeteRun(r.course, r.rivals,
        t0: _seconds, trace: GhostTrace(r.course.route.lengthMeters));
  }

  /// Stops the countdown or the race; the ride itself carries on.
  void cancel() {
    _timer?.cancel();
    final run = state;
    state = null;
    if (run != null && run.started) {
      ref.read(rideSessionProvider.notifier).stopRoute();
    }
  }

  double get _seconds =>
      ref.read(recorderProvider).elapsed.inMilliseconds / 1000;

  void _tick() {
    final run = state, rr = ref.read(routeRunProvider), trace = run?.trace;
    if (run == null || trace == null || run.result != null || rr == null) return;
    if (ref.read(recorderProvider).status != RecStatus.recording) return;
    final trainer = ref.read(trainerControllerProvider);
    trace.add(_seconds - run.t0,
        ref.read(liveRideStatsProvider).distanceMeters - rr.origin,
        watts: trainer.smoothedPower?.round(),
        bpm: trainer.latest?.heartRate);
    if (!trace.finished) return;
    final now = DateTime.now();
    final g = Ghost(
        id: now.millisecondsSinceEpoch.toString(),
        course: run.course.id,
        name: rideTitle(now),
        t: trace.t,
        d: trace.d,
        power: trace.power,
        hr: trace.hr,
        kg: ref.read(riderProfileProvider).weightKg,
        mine: true);
    state = CompeteRun(run.course, run.rivals, t0: run.t0, trace: trace, result: g);
    ref.read(ghostsProvider.notifier).addMine(g).catchError((_) {});
  }
}

/// A rival's gap, and how hard they were working at this point of the race.
typedef Standing = ({Ghost ghost, GhostGap gap, int? watts, int? bpm});

/// Each rival against the race in progress (none before the start); frozen
/// at your finish, where a positive gap is how much faster you were.
final raceStandingsProvider = Provider<List<Standing>>((ref) {
  final run = ref.watch(competeProvider);
  final p = ref.watch(routeProgressProvider);
  if (run == null || !run.started || p == null) return const [];
  final res = run.result;
  final elapsed = res?.seconds ??
      ref.watch(recorderProvider.select((r) => r.elapsed)).inMilliseconds /
              1000 -
          run.t0;
  final meters = res?.meters ?? p.meters;
  return [
    for (final g in run.rivals)
      if (g.effortAt(elapsed) case (:final watts, :final bpm))
        (
          ghost: g,
          gap: gapTo(g, elapsed: elapsed, riderMeters: meters),
          watts: watts,
          bpm: bpm,
        )
  ];
});
