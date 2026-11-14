import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/dashboard_layout.dart';
import '../core/ride_recording.dart';
import 'dashboard_grid.dart';
import 'dashboard_layout_controller.dart';
import 'focus_views.dart';
import 'layout.dart';
import 'ride_view_controller.dart';
import 'navigation.dart';
import 'route_controller.dart';
import 'plan_screen.dart';
import 'recorder_controller.dart';
import 'recording_panel.dart';
import 'trainer_controller.dart';

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  bool _editing = false;

  /// Holds focus for the keyboard shortcuts, and gets it back after every
  /// click, so Space never re-presses whichever button was clicked last.
  final _focus = FocusNode(debugLabel: 'dashboard shortcuts');

  @override
  void initState() {
    super.initState();
    // Keep the screen (and browser tab) awake during a ride.
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _focus.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  /// Keys act only while this screen is on top: not under a dialog or a
  /// pushed screen, and not while another page is open in the dock (the
  /// dashboard stays alive behind it).
  VoidCallback _guarded(VoidCallback f) => () {
        final onTop = ModalRoute.of(context)?.isCurrent ?? true;
        if (onTop && ref.read(pageProvider) == AppPage.ride) f();
      };

  /// A plan owns the target while it runs.
  void _nudge(int watts) {
    if (ref.read(targetLockProvider) == null) {
      ref.read(trainerControllerProvider.notifier).adjustTarget(watts);
    }
  }

  void _toggleRecording() {
    final recorder = ref.read(recorderProvider.notifier);
    switch (ref.read(recorderProvider).status) {
      case RecStatus.idle:
        recorder.start();
      case RecStatus.recording:
        recorder.pause();
      case RecStatus.paused:
        recorder.resume();
    }
  }

  /// Disconnecting mid-ride pauses the recording, so it asks first.
  Future<void> _disconnect() async {
    if (ref.read(recorderProvider).status != RecStatus.idle) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Disconnect the trainer?'),
          content: const Text('Your recording pauses. You can reconnect and resume it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep riding')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Disconnect')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(trainerControllerProvider.notifier).disconnect();
  }

  /// The trainer, the view choice, Edit layout (dashboard only) and
  /// Disconnect, behind one button on the record bar.
  Widget _viewMenu(String? deviceName, RideView view) => PopupMenuButton<Object>(
        tooltip: 'View and trainer',
        // Narrower than the default 48 px, to fit a phone-width record bar.
        style: IconButton.styleFrom(
            minimumSize: const Size(36, 48), padding: EdgeInsets.zero),
        icon: const Icon(Icons.more_vert),
        onSelected: (v) {
          if (v is RideView) {
            _editing = false; // only the dashboard is editable
            ref.read(rideViewProvider.notifier).set(v);
          } else if (v == 'edit') {
            setState(() => _editing = true);
          } else {
            _disconnect();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
              enabled: false,
              child: Row(children: [
                const Icon(Icons.bluetooth_connected, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(deviceName ?? 'Trainer')),
              ])),
          const PopupMenuDivider(),
          for (final v in RideView.values)
            CheckedPopupMenuItem(
                value: v, checked: v == view, child: Text(v.label)),
          if (view == RideView.dashboard && !_editing)
            const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.dashboard_customize_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Edit layout'),
                ])),
          const PopupMenuDivider(),
          PopupMenuItem(
              value: 'disconnect',
              child: Text('Disconnect',
                  style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final deviceName = ref.watch(trainerControllerProvider.select((s) => s.deviceName));
    final error = ref.watch(trainerControllerProvider.select((s) => s.error));
    final theme = Theme.of(context);
    final view = ref.watch(rideViewProvider);
    final active = ref.watch(
        recorderProvider.select((r) => r.status != RecStatus.idle));

    // Controls and tiles read as one workout: outlined together while a
    // ride is being recorded.
    Widget outlined(Widget child) => Container(
          padding: EdgeInsets.all(active ? 12 : 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? theme.colorScheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: child,
        );
    final errorText = error == null
        ? null
        : Text(error, style: TextStyle(color: theme.colorScheme.error));

    return LayoutBuilder(builder: (context, box) {
      final compact = !isWideLayout(box.maxWidth);

      final Widget content;
      if (view == RideView.dashboard) {
        content = ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_editing) ...[
              _EditToolbar(onDone: () => setState(() => _editing = false)),
              const SizedBox(height: 12),
            ],
            outlined(Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const PlanBar(),
              WorkoutBar(trailing: _viewMenu(deviceName, view)),
              const SizedBox(height: 12),
              DashboardGrid(editing: _editing, compact: compact),
            ])),
            if (errorText != null) ...[const SizedBox(height: 12), errorText],
          ],
        );
      } else {
        // Map or chart over fixed metrics, sized to the window so the page
        // does not scroll. Below a minimum height it scrolls rather than
        // squashing the map.
        final minHeight = 330 + MetricStrip.heightFor(compact);
        content = SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: math.max(box.maxHeight - 32, minHeight),
            child: Column(children: [
              Expanded(
                child: outlined(Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PlanBar(),
                      WorkoutBar(trailing: _viewMenu(deviceName, view)),
                      const SizedBox(height: 12),
                      Expanded(
                          child: view == RideView.map
                              ? const MapFocus()
                              : const ChartFocus()),
                      const SizedBox(height: 12),
                      MetricStrip(compact: compact),
                    ])),
              ),
              if (errorText != null) ...[const SizedBox(height: 12), errorText],
            ]),
          ),
        );
      }

      // Keyboard: Space records, pauses or resumes; the arrow keys move the
      // ERG target by 5 W (25 W with Shift). Off while arranging tiles.
      return CallbackShortcuts(
        bindings: _editing
            ? const {}
            : {
                const SingleActivator(LogicalKeyboardKey.space): _guarded(_toggleRecording),
                const SingleActivator(LogicalKeyboardKey.arrowUp): _guarded(() =>
                    _nudge(5)),
                const SingleActivator(LogicalKeyboardKey.arrowDown): _guarded(() =>
                    _nudge(-5)),
                const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): _guarded(() =>
                    _nudge(25)),
                const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): _guarded(() =>
                    _nudge(-25)),
              },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerUp: (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _focus.requestFocus();
            }),
            child: content,
          ),
        ),
      );
    });
  }
}

class _EditToolbar extends ConsumerWidget {
  const _EditToolbar({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(dashboardLayoutProvider);
    final c = ref.read(dashboardLayoutProvider.notifier);
    final unplaced = layout.unplaced;
    final isStandard = layout.toJson() == DashboardLayout.standard.toJson();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Drag tiles to rearrange. The gear resizes a tile or '
                'changes what it shows.'),
            PopupMenuButton<TileKind>(
              enabled: unplaced.isNotEmpty,
              tooltip: unplaced.isEmpty ? 'Everything is already on the dashboard' : 'Add tile',
              onSelected: c.add,
              itemBuilder: (_) => [
                for (final k in unplaced) PopupMenuItem(value: k, child: Text(k.label)),
              ],
              child: Chip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add tile'),
                side: unplaced.isEmpty ? BorderSide.none : null,
              ),
            ),
            TextButton(
              onPressed: isStandard ? null : c.reset,
              child: const Text('Reset to default'),
            ),
            FilledButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
