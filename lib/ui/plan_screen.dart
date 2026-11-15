import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/plan.dart';
import '../core/ride_recording.dart';
import '../devices/trainer.dart';
import 'format.dart';
import 'layout.dart';
import 'plan_controller.dart';
import 'recorder_controller.dart';
import 'navigation.dart';
import 'trainer_controller.dart';
import 'ride_session.dart';

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Plan? old]) async {
    final plan = await Navigator.of(context).push<Plan>(
      MaterialPageRoute(builder: (_) => PlanEditor(initial: old)),
    );
    if (plan != null) ref.read(plansProvider.notifier).save(plan, old: old);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final connected = ref.watch(trainerControllerProvider
        .select((s) => s.status == TrainerStatus.connected));
    final ftp = ref.watch(ftpProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New plan'),
      ),
      body: plans.isEmpty
          ? const Center(child: Text('No plans yet. Make one to ride in ERG.'))
          : ListView(padding: const EdgeInsets.only(top: 8, bottom: 88), children: [
              for (final p in plans)
                ListTile(
                  leading: SizedBox(
                    width: 96,
                    child: PlanPreview(
                        steps: p.expand(),
                        unit: p.percent ? '% FTP' : 'W',
                        height: 48),
                  ),
                  title: Text(p.name),
                  subtitle: Text('${p.expand().length} steps · '
                      '${clock(Duration(seconds: p.totalSeconds))}'
                      '${p.percent ? ' · % FTP' : ''}'),
                  onTap: () => _edit(context, ref, p),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          ref.read(plansProvider.notifier).delete(p),
                    ),
                    IconButton.filled(
                      tooltip: !connected
                          ? 'Connect a trainer to start'
                          : p.percent && ftp == null
                              ? 'Set your FTP in Preferences first'
                              : 'Start and record',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: connected && (!p.percent || ftp != null)
                          ? () {
                              ref.read(rideSessionProvider.notifier).startPlan(p, ftp);
                              ref.read(pageProvider.notifier).state = AppPage.ride;
                            }
                          : null,
                    ),
                  ]),
                ),
            ]),
    );
  }
}

class _StepRow {
  _StepRow(PlanStep s)
      : min = TextEditingController(text: _fmt(s.seconds / 60)),
        from = TextEditingController(text: '${s.from}'),
        to = TextEditingController(text: s.to == s.from ? '' : '${s.to}');
  final TextEditingController min, from, to;

  static String _fmt(double m) =>
      m == m.roundToDouble() ? '${m.round()}' : '$m';
}

class _BlockRows {
  _BlockRows(PlanBlock b)
      : repeat = TextEditingController(text: '${b.repeat}'),
        steps = [for (final s in b.steps) _StepRow(s)];
  final TextEditingController repeat;
  final List<_StepRow> steps;
}

/// Edits a plan as blocks of steps (minutes, start, optional ramp-to), each
/// block repeatable, with a live chart. Pops the finished [Plan].
class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, this.initial});
  final Plan? initial;

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late bool _percent = widget.initial?.percent ?? false;
  late final List<_BlockRows> _blocks = [
    for (final b in widget.initial?.blocks ??
        const [
          PlanBlock([PlanStep(300, 100)])
        ])
      _BlockRows(b),
  ];
  String? _error;

  /// Whatever parses so far, for the live chart; [_save] does the strict check.
  List<PlanStep> _preview() {
    final out = <PlanStep>[];
    for (final b in _blocks) {
      final n = (int.tryParse(b.repeat.text) ?? 1).clamp(1, 99);
      final steps = <PlanStep>[];
      for (final r in b.steps) {
        final m = double.tryParse(r.min.text), a = int.tryParse(r.from.text);
        if (m == null || m <= 0 || a == null) continue;
        steps.add(PlanStep((m * 60).round().clamp(1, 1 << 30), a,
            int.tryParse(r.to.text) ?? a));
      }
      for (var i = 0; i < n; i++) {
        out.addAll(steps);
      }
    }
    return out;
  }

  void _save() {
    final max = _percent ? 300 : 1500;
    final blocks = <PlanBlock>[];
    for (final b in _blocks) {
      final steps = <PlanStep>[];
      final n = int.tryParse(b.repeat.text);
      for (final r in b.steps) {
        final m = double.tryParse(r.min.text);
        final a = int.tryParse(r.from.text);
        final z = r.to.text.isEmpty ? a : int.tryParse(r.to.text);
        if (n == null || n < 1 || m == null || m <= 0 || a == null ||
            z == null || a > max || z > max) {
          return setState(() => _error = 'Each step needs minutes above 0 '
              'and 0–$max ${_percent ? '% FTP' : 'W'}; repeats at least 1.');
        }
        steps.add(PlanStep((m * 60).round().clamp(1, 1 << 30), a, z));
      }
      blocks.add(PlanBlock(steps, repeat: n!));
    }
    final name = _name.text.trim();
    Navigator.of(context)
        .pop(Plan(name.isEmpty ? 'Untitled' : name, blocks, percent: _percent));
  }

  Widget _field(TextEditingController c, String label, {bool decimal = false}) =>
      TextField(
        controller: c,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
              RegExp(decimal ? r'[0-9.]' : r'[0-9]')),
        ],
      );

  Widget _block(int bi, _BlockRows b) {
    final unit = _percent ? '% FTP' : 'W';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 90, child: _field(b.repeat, 'Repeat ×')),
            const Spacer(),
            IconButton(
              tooltip: 'Remove block',
              icon: const Icon(Icons.delete_outline),
              onPressed: _blocks.length == 1
                  ? null
                  : () => setState(() => _blocks.removeAt(bi)),
            ),
          ]),
          for (final (i, r) in b.steps.indexed)
            Row(children: [
              Expanded(child: _field(r.min, 'Minutes', decimal: true)),
              const SizedBox(width: 12),
              Expanded(child: _field(r.from, unit)),
              const SizedBox(width: 12),
              Expanded(child: _field(r.to, 'Ramp to (optional)')),
              IconButton(
                tooltip: 'Remove step',
                icon: const Icon(Icons.close),
                onPressed: b.steps.length == 1
                    ? null
                    : () => setState(() => b.steps.removeAt(i)),
              ),
            ]),
          TextButton.icon(
            onPressed: () => setState(() => b.steps.add(_StepRow(PlanStep(
                ((double.tryParse(b.steps.last.min.text) ?? 5) * 60).round(),
                int.tryParse(b.steps.last.from.text) ?? 100)))),
            icon: const Icon(Icons.add),
            label: const Text('Add step'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nameAndUnit =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Watts')),
          ButtonSegment(value: true, label: Text('% of FTP')),
        ],
        selected: {_percent},
        onSelectionChanged: (s) => setState(() => _percent = s.first),
      ),
    ]);
    final blocks = <Widget>[
      for (final (i, b) in _blocks.indexed) _block(i, b),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() =>
              _blocks.add(_BlockRows(const PlanBlock([PlanStep(300, 100)])))),
          icon: const Icon(Icons.add),
          label: const Text('Add block'),
        ),
      ),
      if (_error != null)
        Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ];
    Widget preview(double height) => PlanPreview(
        steps: _preview(), unit: _percent ? '% FTP' : 'W', height: height);

    // The chart never scrolls away: beside the blocks on a wide window,
    // pinned above them on a narrow one.
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New plan' : 'Edit plan'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: LayoutBuilder(builder: (context, box) {
        if (isWideLayout(box.maxWidth)) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                nameAndUnit,
                const SizedBox(height: 12),
                ...blocks,
              ]),
            ),
            SizedBox(
              width: 520,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: preview(260),
              ),
            ),
          ]);
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [nameAndUnit, const SizedBox(height: 12), preview(110)]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: blocks),
          ),
        ]);
      }),
    );
  }
}

/// Shown on the dashboard while a plan runs.
class PlanBar extends ConsumerWidget {
  const PlanBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(planRunProvider);
    final step = run?.step;
    if (run == null || step == null) return const SizedBox.shrink();
    final paused = ref.watch(
        recorderProvider.select((r) => r.status != RecStatus.recording));
    final connected = ref.watch(trainerControllerProvider
        .select((s) => s.status == TrainerStatus.connected));
    final c = ref.read(rideSessionProvider.notifier);
    final rec = ref.read(recorderProvider.notifier);
    final left = run.steps.endOf(step) - run.elapsed;
    final s = run.steps[step];
    final watts = s.from == s.to ? '${s.from} W' : '${s.from}→${s.to} W';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${run.name} · step ${step + 1}/${run.steps.length}'
                ' · $watts · ${clock(Duration(seconds: left))} left'
                '${paused ? ' · paused' : ''}',
              ),
            ),
            IconButton(
              tooltip: paused ? 'Resume' : 'Pause',
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
              onPressed: paused ? (connected ? rec.resume : null) : rec.pause,
            ),
            IconButton(
                tooltip: 'Skip step',
                icon: const Icon(Icons.skip_next),
                onPressed: c.skipPlanStep),
            IconButton(
                tooltip: 'Stop plan (keeps recording)',
                icon: const Icon(Icons.stop),
                onPressed: c.stopPlan),
          ]),
          LinearProgressIndicator(value: run.elapsed / run.steps.totalSeconds),
        ]),
      ),
    );
  }
}

/// The shape of a plan: target over time, in the plan's own unit.
class PlanPreview extends StatelessWidget {
  const PlanPreview(
      {super.key, required this.steps, required this.unit, this.height = 120});

  final List<PlanStep> steps;
  final String unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Plan chart, ${clock(Duration(seconds: steps.totalSeconds))}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
            painter: _PreviewPainter(
                steps, unit, scheme.primary, scheme.onSurfaceVariant)),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.steps, this.unit, this.color, this.textColor);
  final List<PlanStep> steps;
  final String unit;
  final Color color, textColor;

  void _text(Canvas c, String s, Offset at,
      {bool right = false, bool bottom = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: textColor, fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(at.dx - (right ? tp.width : 0), at.dy - (bottom ? tp.height : 0)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty) return;
    final small = size.height < 80; // thumbnail: shape only
    final top = small ? 4.0 : 14.0, bottom = small ? 4.0 : 16.0;
    final total = steps.totalSeconds;
    final peak = steps.fold(0, (m, s) => [m, s.from, s.to].reduce((a, b) => a > b ? a : b));
    final yMax = (peak == 0 ? 1 : peak) * 1.1;
    final pts = steps.outline(0);
    Offset p((double, double) q) => Offset(size.width * q.$1 / total,
        size.height - bottom - (size.height - top - bottom) * q.$2 / yMax);
    final line = Path()..moveTo(p(pts.first).dx, p(pts.first).dy);
    for (final q in pts.skip(1)) {
      line.lineTo(p(q).dx, p(q).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height - bottom)
      ..lineTo(0, size.height - bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    if (small) return;
    _text(canvas, 'peak $peak $unit', Offset.zero);
    _text(canvas, '0:00', Offset(0, size.height), bottom: true);
    _text(canvas, clock(Duration(seconds: total)), Offset(size.width, size.height),
        right: true, bottom: true);
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
