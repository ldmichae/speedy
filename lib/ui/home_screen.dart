import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../devices/trainer.dart';
import 'connect_view.dart';
import 'dashboard_view.dart';
import 'history_screen.dart';
import 'layout.dart';
import 'plan_screen.dart';
import 'route_screen.dart';
import 'preferences_screen.dart';
import 'trainer_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(
        trainerControllerProvider.select((s) => s.status == TrainerStatus.connected));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor Cycling'),
        actions: const [RoutesButton(), PlansButton(), HistoryButton(), PreferencesButton()],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: connected ? wideContentMaxWidth : 720),
            child: connected
                ? const DashboardView()
                : const ConnectView(),
          ),
        ),
      ),
    );
  }
}
