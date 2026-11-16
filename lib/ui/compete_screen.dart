import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/course.dart';
import '../core/elevation.dart';
import '../core/ghost.dart';
import '../core/units.dart';
import '../devices/trainer.dart';
import 'compete_controller.dart';
import 'elevation_chart.dart';
import 'format.dart';
import 'navigation.dart';
import 'ride_view_controller.dart';
import 'route_controller.dart';
import 'trainer_controller.dart';
import 'units_controller.dart';

/// One colour per rival, in the order they were picked (cycling past six).
const ghostColors = [
  Color(0xFFDC2626),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFEA580C),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
];
Color ghostColor(int i) => ghostColors[i % ghostColors.length];

String _time(double s) => clock(Duration(milliseconds: (s * 1000).round()));

/// The Compete tab: the catalog of courses, with your best on each.
class CompeteScreen extends ConsumerWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ghosts = ref.watch(ghostsProvider).valueOrNull ?? const <Ghost>[];
    final units = ref.watch(rideUnitsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'import-ghost',
        onPressed: () => importGhost(context, ref),
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('Import ghost'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          Text('Ride a course and your effort becomes a ghost to race next '
              'time. Share it, or import a friend\'s, to race each other.'),
          const SizedBox(height: 12),
          for (final c in courses) ...[
            Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CourseScreen(course: c))),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(c.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium)),
                          if (bestOf(ghosts, c.id) case final b?)
                            Chip(
                                avatar: const Icon(Icons.timer_outlined),
                                label: Text('Best ${_time(b.seconds)}')),
                        ]),
                        Text(c.blurb),
                        const SizedBox(height: 4),
                        Text(
                            '${routeDistanceText(c.lengthMeters, units)} · '
                            '↑ ${elevationText(c.route.elevation!.climb, units)}',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        ElevationChart(
                            profile: c.route.elevation!, height: 40),
                      ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Asks for a ghost file and adds it; the outcome is shown in a snackbar.
Future<void> importGhost(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
  try {
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['json']);
    if (file == null) return;
    final g = await ref.read(ghostsProvider.notifier).import(
        utf8.decode(await file.readAsBytes(), allowMalformed: true));
    say('Added ${g.name} on ${courseById(g.course)!.name}.');
  } on FormatException catch (e) {
    say(e.message);
  } catch (_) {
    say('Could not import that file.');
  }
}

/// One course: its profile, the ghosts you can race on it, and Race.
class CourseScreen extends ConsumerStatefulWidget {
  const CourseScreen({super.key, required this.course});
  final Course course;

  @override
  ConsumerState<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends ConsumerState<CourseScreen> {
  Set<String>? _picked; // null until ghosts load; then your best is ticked

  Course get _c => widget.course;

  void _race(List<Ghost> ghosts) {
    final rivals = [
      for (final g in ghosts)
        if (_picked!.contains(g.id)) g
    ];
    // Only lines it up: the rider warms up, then starts it from the race view.
    ref.read(competeProvider.notifier).stage(_c, rivals);
    // The race view is the Map view's tile, so show that.
    ref.read(rideViewProvider.notifier).set(RideView.map);
    ref.read(pageProvider.notifier).state = AppPage.ride;
    Navigator.of(context).pop();
  }

  Future<void> _delete(Ghost g, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $label?'),
        content: const Text('This ghost will be gone. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    _picked?.remove(g.id);
    await ref.read(ghostsProvider.notifier).delete(g.id);
  }

  /// Saves a ghost file to send to a friend. The name inside is shown to
  /// them, so it is asked for rather than guessed.
  Future<void> _share(Ghost g) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
        context: context, builder: (_) => const _NameDialog());
    if (name == null || name.trim().isEmpty) return;
    try {
      final safe = '${_c.name} ${name.trim()}'.replaceAll(RegExp(r'[^\w\- ]'), '_');
      final saved = await FilePicker.saveFile(
        fileName: '$safe.ghost.json',
        bytes: utf8.encode(jsonEncode(g.named(name.trim()).toJson())),
        mimeType: 'application/json',
      );
      if (saved != null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Saved. Send the file to a friend to import.')));
      }
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save the file.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(ghostsProvider);
    final units = ref.watch(rideUnitsProvider);
    final list = all.valueOrNull ?? const <Ghost>[];
    final ghosts = [
      for (final g in list)
        if (g.course == _c.id) g
    ]..sort((a, b) => a.seconds.compareTo(b.seconds));
    if (all.hasValue) _picked ??= {if (bestOf(list, _c.id) case final b?) b.id};
    final picked = _picked ?? const <String>{};
    final profile = _c.route.elevation!;

    return Scaffold(
      appBar: AppBar(title: Text(_c.name), actions: [
        IconButton(
          tooltip: 'Import ghost',
          icon: const Icon(Icons.file_open_outlined),
          onPressed: () => importGhost(context, ref),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.flag),
            label: Text(picked.isEmpty
                ? 'Go to start line (no ghosts)'
                : 'Go to start line · ${picked.length} '
                    'ghost${picked.length == 1 ? '' : 's'}'),
            onPressed: all.hasValue ? () => _race(ghosts) : null,
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(_c.blurb),
        const SizedBox(height: 8),
        Text('${routeDistanceText(_c.lengthMeters, units)} · '
            '${elevationSummary(profile, units)}'),
        const SizedBox(height: 12),
        ElevationChart(profile: profile, height: 140),
        const SizedBox(height: 16),
        Text('Race against', style: Theme.of(context).textTheme.titleMedium),
        if (ghosts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text("No ghosts yet. Ride it once to set one, or import a "
                "friend's."),
          ),
        for (final g in ghosts)
          CheckboxListTile(
            value: picked.contains(g.id),
            onChanged: (v) => setState(() =>
                v == true ? _picked?.add(g.id) : _picked?.remove(g.id)),
            title: Text(ghostLabel(g, list)),
            subtitle: Text(g.mine ? '${_time(g.seconds)} · ${g.name}' : _time(g.seconds)),
            secondary: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Share ghost',
                icon: const Icon(Icons.ios_share),
                onPressed: () => _share(g),
              ),
              IconButton(
                tooltip: 'Delete ghost',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(g, ghostLabel(g, list)),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: _c,
          autofocus: true,
          decoration: const InputDecoration(
              helperText: 'Shown to whoever races this ghost'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _c.text),
              child: const Text('Save file')),
        ],
      );
}

/// The race: the course profile with you and every ghost on it, and how far
/// ahead or behind each one you are. Before the start it waits at the line
/// (warm up as long as you like), then counts down. Fills its space.
class RaceView extends ConsumerWidget {
  const RaceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(competeProvider);
    final progress = ref.watch(routeProgressProvider);
    final standings = ref.watch(raceStandingsProvider);
    final units = ref.watch(rideUnitsProvider);
    final all = ref.watch(ghostsProvider).valueOrNull ?? const <Ghost>[];
    final connected = ref.watch(trainerControllerProvider
        .select((s) => s.status == TrainerStatus.connected));
    if (run == null) return const SizedBox.shrink();
    // Before the start another route may still be running: ignore it.
    final p = run.started ? progress : null;
    final theme = Theme.of(context);
    final res = run.result;
    final len = run.course.route.lengthMeters;
    final meters = p?.meters ?? 0.0;
    final head = res != null
        ? '${run.course.name} · finished in ${_time(res.seconds)}'
        : p != null
            ? '${run.course.name} · ${routeDistanceText(len - meters, units)} to go'
            : '${run.course.name} · at the start line';

    String gap(GhostGap g) {
      if (res == null) return gapText(g);
      final s = (g.seconds ?? 0).abs().round();
      return g.ahead ? 'beat by $s s' : 'lost by $s s';
    }

    Widget row(int i, Ghost g, Widget trailing) => Row(children: [
          Icon(Icons.circle, size: 12, color: ghostColor(i)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(ghostLabel(g, all),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          trailing,
        ]);

    final countdown = run.countdown;
    final startLine = p != null
        ? null
        : countdown != null
            ? Semantics(
                liveRegion: true,
                label: 'Starting in $countdown',
                child: Text('$countdown',
                    style: theme.textTheme.displayLarge
                        ?.copyWith(fontWeight: FontWeight.bold)))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  icon: const Icon(Icons.flag),
                  label: const Text('Start race'),
                  onPressed: connected
                      ? ref.read(competeProvider.notifier).startCountdown
                      : null,
                ),
                const SizedBox(height: 4),
                Text(connected
                    ? 'Warm up as long as you like. '
                        '${CompeteController.countdownSeconds} s countdown.'
                    : 'Connect a trainer to start'),
              ]);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(head,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium)),
            IconButton.filledTonal(
              tooltip: p != null ? 'Stop race' : 'Leave the start line',
              icon: const Icon(Icons.close),
              onPressed: ref.read(competeProvider.notifier).cancel,
            ),
          ]),
          if (p == null)
            for (final (i, g) in run.rivals.indexed)
              row(i, g, Text('to beat ${_time(g.seconds)}'))
          else
            for (final (i, s) in standings.indexed)
              row(
                  i,
                  s.ghost,
                  // Arrow and words carry the direction, not colour.
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(s.gap.ahead ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16),
                    Text(gap(s.gap), style: theme.textTheme.titleMedium),
                  ])),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (_, box) => ElevationChart(
                    profile: run.course.route.elevation!,
                    height: box.maxHeight,
                    riderMeters: meters,
                    markers: [
                      for (var i = 0; i < run.rivals.length; i++)
                        (
                          p == null
                              ? 0.0
                              : (meters - standings[i].gap.meters)
                                  .clamp(0.0, len)
                                  .toDouble(),
                          ghostColor(i)
                        ),
                    ],
                  ),
                ),
              ),
              if (startLine != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: theme.colorScheme.surface.withValues(alpha: 0.75),
                    child: Center(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: startLine))),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
