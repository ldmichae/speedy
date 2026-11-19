import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/plan.dart';
import '../core/ride_recording.dart';
import '../core/route.dart';
import '../core/tour.dart';
import 'recorder_controller.dart';
import 'tour_controller.dart';
import 'trainer_controller.dart';

/// A plan being ridden, in watts. It rides on the recording's clock, so
/// pausing (or losing the trainer, which pauses the recording) pauses it.
/// [origin] is the recording second the plan's second 0 falls on.
class PlanRun {
  const PlanRun(this.name, this.steps, this.origin, this.elapsed);
  final String name;
  final List<PlanStep> steps;
  final int origin;
  final int elapsed;

  int? get step => steps.indexAt(elapsed);
}

/// A course being ridden (one route, or a tour). [origin] is the ride
/// distance (metres) at which the course's start line sits, so riding
/// mid-recording starts it at zero, or at the chosen stage of a tour.
/// With [simulate] the trainer applies the course's grade as resistance.
class RouteRun {
  const RouteRun(this.course, this.origin, {this.simulate = false});
  final RideCourse course;
  final double origin;
  final bool simulate;
}

/// The Plan and the Route being ridden, if any.
class RideSessionState {
  const RideSessionState({this.plan, this.route});
  final PlanRun? plan;
  final RouteRun? route;
}

/// What a plan does on one recorder update: its next state (null once it
/// has ended; the ride goes on at the last target) and the target to send,
/// if one is due. [applied] is the last target sent, so a step is sent once.
({PlanRun? next, int? send}) tickPlan(PlanRun run,
    {required int recorderSeconds, required bool recording, int? applied}) {
  final elapsed = recorderSeconds - run.origin;
  final watts = run.steps.wattsAt(elapsed);
  if (watts == null) return (next: null, send: null);
  return (
    next: PlanRun(run.name, run.steps, run.origin, elapsed),
    send: recording && watts != applied ? watts : null,
  );
}

/// What a route does on one recorder update.
class RouteTick {
  const RouteTick(
      {required this.meters,
      required this.doneUpTo,
      this.completed = const [],
      this.prefetch,
      this.grade});

  /// How far along the course the rider is.
  final double meters;

  /// Tour stages before this index are ticked off (including [completed]).
  final int doneUpTo;

  /// Tour stages passed since the last tick.
  final List<int> completed;

  /// The tour whose elevation should be ready for [meters].
  final Tour? prefetch;

  /// Road grade to ride at, when the run is simulated.
  final double? grade;
}

/// Pure: where the rider is, which stages they passed, and what grade to
/// ride. Null while the recording is not running.
RouteTick? tickRoute(RouteRun run,
    {required double rideMeters,
    required bool recording,
    required int doneUpTo}) {
  if (!recording) return null;
  final c = run.course;
  final len = c.lengthMeters;
  final meters = (rideMeters - run.origin).clamp(0.0, len).toDouble();
  var done = doneUpTo;
  final completed = <int>[];
  if (c is Tour) {
    final upTo = meters >= len ? c.stageCount : c.stageAt(meters);
    for (var i = done; i < upTo; i++) {
      completed.add(i);
    }
    if (upTo > done) done = upTo;
  }
  return RouteTick(
    meters: meters,
    doneUpTo: done,
    completed: completed,
    prefetch: c is Tour ? c : null,
    // Flat at the finish, and wherever elevation has not loaded yet.
    grade: run.simulate ? (meters >= len ? 0.0 : (c.gradeAt(meters) ?? 0.0)) : null,
  );
}

final rideSessionProvider =
    NotifierProvider<RideSession, RideSessionState>(RideSession.new);

final planRunProvider = Provider<PlanRun?>(
    (ref) => ref.watch(rideSessionProvider.select((s) => s.plan)));

final routeRunProvider = Provider<RouteRun?>(
    (ref) => ref.watch(rideSessionProvider.select((s) => s.route)));

/// What owns the ERG target, if anything: the manual controls are locked.
enum TargetLock { plan, simulation }

final targetLockProvider = Provider<TargetLock?>((ref) {
  if (ref.watch(planRunProvider) != null) return TargetLock.plan;
  if (ref.watch(routeRunProvider.select((r) => r?.simulate ?? false))) {
    return TargetLock.simulation;
  }
  return null;
});

/// Owns the Plan and the Route being ridden, and is the one place that
/// decides what the trainer is told: the Plan's ERG target, or a simulated
/// Route's grade. A Plan and a simulation never run together; the other
/// kind of run may carry on beside either (a map under a Plan).
class RideSession extends Notifier<RideSessionState> {
  int? _applied; // last plan target sent
  int _doneUpTo = 0; // tour stages before this index are marked ridden
  double _from = 0, _at = 0; // where on the course this ride began, and is

  PlanRun? get _plan => state.plan;
  RouteRun? get _route => state.route;

  @override
  RideSessionState build() {
    ref.listen(recorderProvider, (prev, next) {
      if (next.status == RecStatus.idle) {
        return _stopAll(); // saved or discarded
      }
      if (prev?.status != RecStatus.recording) _applied = null; // resumed
      _syncPlan();
      _syncRoute();
    });
    // A tour being ridden gains elevation as stages load: use the new copy.
    ref.listen(toursProvider, (_, next) {
      final r = _route, c = r?.course;
      if (r == null || c is! Tour) return;
      final fresh = next.valueOrNull?.where((t) => t.id == c.id).firstOrNull;
      if (fresh != null && fresh.stageCount >= c.stageCount) {
        state = RideSessionState(
            plan: _plan,
            route: RouteRun(fresh.throughStage(c.stageCount - 1), r.origin,
                simulate: r.simulate));
      }
    });
    return const RideSessionState();
  }

  /// Starts recording (or resumes it) and rides [plan]; [ftp] is needed for
  /// a percent plan. A plan owns the target, so it ends any simulation.
  void startPlan(Plan plan, int? ftp) {
    endSimulation();
    ref.read(recorderProvider.notifier).startOrResume();
    _applied = null;
    state = RideSessionState(
        plan: PlanRun(plan.name, plan.resolve(ftp),
            ref.read(recorderProvider).elapsed.inSeconds, 0),
        route: _route);
    _syncPlan();
  }

  /// Jumps to the start of the next step; ends the plan after the last one.
  void skipPlanStep() {
    final r = _plan;
    final i = r?.step;
    if (r == null || i == null) return;
    state = RideSessionState(
        plan: PlanRun(
            r.name, r.steps, r.origin - (r.steps.endOf(i) - r.elapsed), r.elapsed),
        route: _route);
    _syncPlan();
  }

  void stopPlan() => state = RideSessionState(route: _route);

  /// Starts recording (or resumes it) and puts the rider at the start of
  /// [course], or of [stage] for a tour (the ride ends with that stage; see
  /// [continueTour]), or [at] metres into the course. [simulate] takes the target from any
  /// plan; where elevation is not loaded yet it rides flat.
  void startRoute(RideCourse course,
      {bool simulate = false, int stage = 0, double? at}) {
    final from = at ?? course.stageStart(stage);
    stage = course.stageAt(from);
    final sim =
        simulate && (course.stageCount > 1 || course.elevationAt(0) != null);
    if (sim) stopPlan();
    ref.read(recorderProvider.notifier).startOrResume();
    _doneUpTo = stage;
    _from = _at = from;
    state = RideSessionState(
        plan: _plan,
        route: RouteRun(
            course is Tour ? course.throughStage(stage) : course,
            ref.read(liveRideStatsProvider).distanceMeters - from,
            simulate: sim));
    _syncRoute();
  }

  /// Adds the tour's next stage to the end of the one just finished. It
  /// starts where the rider is now, so riding on while asked skips nothing.
  void continueTour() {
    final r = _route, c = r?.course;
    if (r == null || c is! Tour) return;
    final full = ref.read(toursProvider.notifier).byId(c.id);
    if (full == null || full.stageCount <= c.stageCount) return;
    state = RideSessionState(
        plan: _plan,
        route: RouteRun(
            full.throughStage(c.stageCount),
            ref.read(liveRideStatsProvider).distanceMeters - c.lengthMeters,
            simulate: r.simulate));
    _syncRoute();
  }

  /// Back to ERG at the last target; the route and map carry on.
  void endSimulation() {
    final r = _route;
    if (r == null || !r.simulate) return;
    state = RideSessionState(plan: _plan, route: RouteRun(r.course, r.origin));
    _leaveSim();
  }

  void stopRoute() {
    _saveResume();
    final wasSim = _route?.simulate ?? false;
    state = RideSessionState(plan: _plan);
    if (wasSim) _leaveSim();
  }

  void _stopAll() {
    stopPlan();
    stopRoute();
  }

  void _leaveSim() {
    final t = ref.read(trainerControllerProvider.notifier);
    t.setTarget(ref.read(trainerControllerProvider).targetWatts);
  }

  void _syncPlan() {
    final r = _plan;
    if (r == null) return;
    final rec = ref.read(recorderProvider);
    final t = tickPlan(r,
        recorderSeconds: rec.elapsed.inSeconds,
        recording: rec.status == RecStatus.recording,
        applied: _applied);
    if (t.next == null) return stopPlan(); // the ride goes on at the last target
    state = RideSessionState(plan: t.next, route: _route);
    if (t.send != null) {
      _applied = t.send;
      ref.read(trainerControllerProvider.notifier).setTarget(t.send!);
    }
  }

  void _syncRoute() {
    final r = _route;
    if (r == null) return;
    final t = tickRoute(r,
        rideMeters: ref.read(liveRideStatsProvider).distanceMeters,
        recording: ref.read(recorderProvider).status == RecStatus.recording,
        doneUpTo: _doneUpTo);
    if (t == null) return;
    _doneUpTo = t.doneUpTo;
    _at = t.meters;
    for (final i in t.completed) {
      _complete(r.course as Tour, i);
    }
    if (t.prefetch != null) {
      // The whole tour, so the next stage is ready if the rider rides on.
      final full = ref.read(toursProvider.notifier).byId(t.prefetch!.id);
      ref
          .read(tourElevationProvider.notifier)
          .prefetch(full ?? t.prefetch!, t.meters);
    }
    if (t.grade != null) {
      ref.read(trainerControllerProvider.notifier).setGrade(t.grade!);
    }
  }

  /// A tour ride that stopped partway through a stage is picked up there
  /// next time; one that ended at a stage's finish clears the point. A ride
  /// that went nowhere leaves any earlier point alone.
  void _saveResume() {
    final c = _route?.course;
    if (c is! Tour || _at <= _from) return;
    final mid = _at < c.lengthMeters ? _at : null;
    ref
        .read(toursProvider.notifier)
        .setResume(c.id, mid)
        .catchError((_) {}); // losing a resume point is not worth an error
  }

  /// Ticks a stage off. If the write fails, the stage is tried again on the
  /// next update rather than lost.
  Future<void> _complete(Tour tour, int index) async {
    try {
      await ref.read(toursProvider.notifier).markCompleted(tour.id, index);
    } catch (_) {
      if (index < _doneUpTo) _doneUpTo = index;
    }
  }
}
