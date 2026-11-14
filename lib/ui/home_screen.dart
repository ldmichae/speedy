import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../devices/trainer.dart';
import 'connect_view.dart';
import 'dashboard_view.dart';
import 'history_screen.dart';
import 'preferences_screen.dart';
import 'trainer_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(trainerControllerProvider.select((s) => s.status));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor Cycling'),
        actions: const [HistoryButton(), PreferencesButton()],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: status == TrainerStatus.connected
                ? const DashboardView()
                : const ConnectView(),
          ),
        ),
      ),
    );
  }
}
