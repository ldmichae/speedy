import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/plan.dart';
import '../core/prefs.dart';
import '../core/ride_recording.dart';
import 'recorder_controller.dart';
import 'route_controller.dart';
import 'trainer_controller.dart';

/// Functional threshold power in watts; null until the rider sets it.
final ftpProvider = NotifierProvider<FtpController, int?>(FtpController.new);

class FtpController extends PersistedNotifier<int?> {
  static const _key = 'ftp';
  static const range = (50, 600);

  @override
  int? get defaults => null;

  @override
  int? read(SharedPreferences p) => p.getInt(_key);

  @override
  Future<void> write(SharedPreferences p, int? v) =>
      v == null ? p.remove(_key) : p.setInt(_key, v);

  void set(int? watts) => put(watts);
}

final plansProvider =
    NotifierProvider<PlansController, List<Plan>>(PlansController.new);

class PlansController extends PersistedNotifier<List<Plan>> {
  static const _key = 'plans';

  @override
  List<Plan> get defaults => const [];

  @override
  List<Plan>? read(SharedPreferences p) {
    try {
      final raw = p.getString(_key);
      if (raw == null) return null;
      return [
        for (final j in jsonDecode(raw) as List) Plan.fromJson(j),
      ].whereType<Plan>().toList();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SharedPreferences p, List<Plan> v) =>
      p.setString(_key, jsonEncode([for (final x in v) x.toJson()]));

  /// Replaces [old] with [plan], or appends it when [old] is null.
  void save(Plan plan, {Plan? old}) {
    final i = old == null ? -1 : state.indexOf(old);
    put(i < 0 ? [...state, plan] : ([...state]..[i] = plan));
  }

  void delete(Plan plan) => put([...state]..remove(plan));
}

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

final planRunProvider = NotifierProvider<PlanRunner, PlanRun?>(PlanRunner.new);

class PlanRunner extends Notifier<PlanRun?> {
  int? _applied; // last target sent, so a step is sent once

  @override
  PlanRun? build() {
    ref.listen(recorderProvider, (prev, next) {
      if (state == null) return;
      if (next.status == RecStatus.idle) return stop(); // saved or discarded
      if (prev?.status != RecStatus.recording) _applied = null; // resumed
      _sync();
    });
    return null;
  }

  /// Starts recording (or resumes it) and rides [plan]; [ftp] is needed for
  /// a percent plan.
  void start(Plan plan, int? ftp) {
    ref.read(routeRunProvider.notifier).endSimulation(); // a plan owns the target
    ref.read(recorderProvider.notifier).startOrResume();
    _applied = null;
    state = PlanRun(plan.name, plan.resolve(ftp),
        ref.read(recorderProvider).elapsed.inSeconds, 0);
    _sync();
  }

  /// Jumps to the start of the next step; ends the plan after the last one.
  void skip() {
    final r = state;
    final i = r?.step;
    if (r == null || i == null) return;
    state = PlanRun(r.name, r.steps, r.origin - (r.steps.endOf(i) - r.elapsed), r.elapsed);
    _sync();
  }

  void stop() => state = null;

  void _sync() {
    final r = state!;
    final elapsed = ref.read(recorderProvider).elapsed.inSeconds - r.origin;
    final watts = r.steps.wattsAt(elapsed);
    if (watts == null) return stop(); // the ride goes on at the last target
    state = PlanRun(r.name, r.steps, r.origin, elapsed);
    if (ref.read(recorderProvider).status == RecStatus.recording &&
        watts != _applied) {
      _applied = watts;
      ref.read(trainerControllerProvider.notifier).setTarget(watts);
    }
  }
}
