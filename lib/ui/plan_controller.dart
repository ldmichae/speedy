import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/plan.dart';
import '../core/prefs.dart';

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
