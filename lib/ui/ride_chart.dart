import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';
import '../core/ride_recording.dart';
import '../core/units.dart';

/// What the user has chosen to see on the ride chart.
class ChartSettings {
  const ChartSettings({
    this.visible = const {
      RideMetric.target,
      RideMetric.power,
      RideMetric.cadence,
    },
    this.window,
  });

  final Set<RideMetric> visible;

  /// Show only the most recent [window]; null shows the whole ride.
  final Duration? window;

  ChartSettings copyWith({Set<RideMetric>? visible, Duration? window, bool clearWindow = false}) =>
      ChartSettings(
        visible: visible ?? this.visible,
        window: clearWindow ? null : (window ?? this.window),
      );
}

final chartSettingsProvider =
    NotifierProvider<ChartSettingsController, ChartSettings>(
        ChartSettingsController.new);

class ChartSettingsController extends PersistedNotifier<ChartSettings> {
  static const _metricsKey = 'chartMetrics';
  static const _windowKey = 'chartWindowSeconds';

  @override
  ChartSettings get defaults => const ChartSettings();

  @override
  ChartSettings? read(SharedPreferences p) {
    final names = p.getStringList(_metricsKey);
    final secs = p.getInt(_windowKey);
    if (names == null && secs == null) return null;
    return ChartSettings(
      visible: names == null
          ? defaults.visible
          : {for (final m in RideMetric.values) if (names.contains(m.name)) m},
      window: secs != null && secs > 0 ? Duration(seconds: secs) : null,
    );
  }

  @override
  Future<void> write(SharedPreferences p, ChartSettings v) async {
    await p.setStringList(_metricsKey, [for (final m in v.visible) m.name]);
    await p.setInt(_windowKey, v.window?.inSeconds ?? 0);
  }

  void toggle(RideMetric m) {
    final next = {...state.visible};
    next.contains(m) ? next.remove(m) : next.add(m);
    put(state.copyWith(visible: next));
  }

  void setWindow(Duration? w) =>
      put(w == null ? state.copyWith(clearWindow: true) : state.copyWith(window: w));
}

class RideChart extends StatefulWidget {
  const RideChart({
    super.key,
    required this.samples,
    required this.settings,
    this.units = UnitSystem.metric,
  });

  final List<RideSample> samples;
  final ChartSettings settings;

  /// Units for speed; every other series has one unit.
  final UnitSystem units;

  @override
  State<RideChart> createState() => _RideChartState();
}

class _RideChartState extends State<RideChart> {
  /// Mouse x within the chart, or null when the pointer is elsewhere.
  double? _hoverX;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metrics = [
      for (final m in RideMetric.values)
        if (widget.settings.visible.contains(m)) m
    ];
    return MouseRegion(
      onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
      onExit: (_) => setState(() => _hoverX = null),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RideChartPainter(
            samples: widget.samples,
            metrics: metrics,
            window: widget.settings.window,
            gridColor: scheme.outlineVariant,
            textColor: scheme.onSurfaceVariant,
            system: widget.units,
            hoverX: _hoverX,
            tooltipColor: scheme.surfaceContainerHighest,
            tooltipTextColor: scheme.onSurface,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// The sample closest in time to [t] (samples are in time order), or null if
/// there are none.
RideSample? nearestSample(List<RideSample> samples, double t) {
  if (samples.isEmpty) return null;
  var lo = 0, hi = samples.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (samples[mid].t < t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo > 0 && t - samples[lo - 1].t <= samples[lo].t - t) return samples[lo - 1];
  return samples[lo];
}

/// One tooltip line per visible metric: its label and value with unit, or
/// "—" when the sample has no value for it.
List<(RideMetric, String)> hoverRows(
    RideSample s, List<RideMetric> metrics, UnitSystem system) {
  return [
    for (final m in metrics)
      (
        m,
        switch (m.valueOf(s, system)) {
          null => '—',
          final v => '${m == RideMetric.speed ? v.toStringAsFixed(1) : v.round()}'
              ' ${m.unitIn(system)}',
        }
      )
  ];
}

class _RideChartPainter extends CustomPainter {
  _RideChartPainter({
    required this.samples,
    required this.metrics,
    required this.window,
    required this.gridColor,
    required this.textColor,
    required this.system,
    required this.hoverX,
    required this.tooltipColor,
    required this.tooltipTextColor,
  });

  final List<RideSample> samples;
  final List<RideMetric> metrics;
  final Duration? window;
  final Color gridColor;
  final Color textColor;
  final UnitSystem system;
  final double? hoverX;
  final Color tooltipColor;
  final Color tooltipTextColor;

  static const _divisions = 4;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 40.0, rightPad = 40.0, topPad = 20.0, bottomPad = 22.0;
    final plot = Rect.fromLTRB(
        leftPad, topPad, size.width - rightPad, size.height - bottomPad);
    if (plot.width <= 0 || plot.height <= 0) return;

    // X range: whole ride, or a sliding window ending at the latest sample.
    final tEnd = samples.isEmpty ? 0.0 : samples.last.t;
    final double x0, x1;
    if (window != null) {
      x1 = math.max(tEnd, window!.inSeconds.toDouble());
      x0 = x1 - window!.inSeconds;
    } else {
      x0 = 0;
      x1 = math.max(tEnd, 60);
    }
    final visible = samples.where((s) => s.t >= x0).toList();

    // One y-axis per unit, in the order the units first appear.
    final units = <String>[];
    for (final m in metrics) {
      if (!units.contains(m.unitIn(system))) units.add(m.unitIn(system));
    }
    final axisMax = <String, double>{};
    for (final u in units) {
      var peak = 0.0;
      for (final m in metrics.where((m) => m.unitIn(system) == u)) {
        for (final s in visible) {
          final v = m.valueOf(s, system);
          if (v != null && v > peak) peak = v;
        }
      }
      axisMax[u] = _niceMax(peak);
    }

    // Grid + left/right axis labels. Any further units have no labels, but
    // their lines are still scaled to their own range.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= _divisions; i++) {
      final y = plot.bottom - plot.height * i / _divisions;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      for (var a = 0; a < math.min(units.length, 2); a++) {
        final v = axisMax[units[a]]! * i / _divisions;
        _text(canvas, _fmt(v), a == 0 ? Offset(plot.left - 6, y) : Offset(plot.right + 6, y),
            align: a == 0 ? _Align.right : _Align.left);
      }
    }
    for (var a = 0; a < math.min(units.length, 2); a++) {
      _text(canvas, units[a],
          a == 0 ? Offset(plot.left - 6, plot.top - 11) : Offset(plot.right + 6, plot.top - 11),
          align: a == 0 ? _Align.right : _Align.left);
    }

    // Time axis.
    final span = x1 - x0;
    final tickStep = _timeStep(span);
    for (var t = (x0 / tickStep).ceil() * tickStep; t <= x1; t += tickStep) {
      final x = plot.left + plot.width * (t - x0) / span;
      _text(canvas, _clock(t), Offset(x, plot.bottom + 4), align: _Align.center, dy: 6);
    }

    if (samples.isEmpty || metrics.isEmpty) {
      _text(
        canvas,
        metrics.isEmpty ? 'Select a metric to chart' : 'Waiting for data',
        plot.center,
        align: _Align.center,
      );
      return;
    }

    canvas.save();
    canvas.clipRect(plot.inflate(2));
    for (final m in metrics.reversed) {
      // Reversed so the first-listed metrics (target) end up on top.
      final max = axisMax[m.unitIn(system)]!;
      final paint = Paint()
        ..color = m.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = m.step ? 2.5 : 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      double? prevY;
      // Cadence and speed jitter from reading to reading; drawn raw they
      // swamp the plot, so they are averaged over a few seconds.
      final values = smoothSeries(
        visible,
        [for (final s in visible) m.valueOf(s, system)],
        m.smoothSeconds,
      );
      for (final (i, s) in visible.indexed) {
        final v = values[i];
        if (v == null) {
          prevY = null;
          continue;
        }
        final x = plot.left + plot.width * (s.t - x0) / span;
        final y = plot.bottom - plot.height * (v / max).clamp(0.0, 1.0);
        if (prevY == null) {
          path.moveTo(x, y);
        } else {
          if (m.step) path.lineTo(x, prevY);
          path.lineTo(x, y);
        }
        prevY = y;
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();

    final hx = hoverX;
    if (hx != null && hx >= plot.left && hx <= plot.right) {
      _paintHover(canvas, size, plot, hx, x0, span, visible, axisMax);
    }
  }

  /// Vertical line at the sample nearest the pointer, a dot on each series,
  /// and a tooltip listing every visible metric at that moment.
  void _paintHover(Canvas canvas, Size size, Rect plot, double hx, double x0,
      double span, List<RideSample> visible, Map<String, double> axisMax) {
    final s = nearestSample(visible, x0 + (hx - plot.left) / plot.width * span);
    if (s == null) return;
    final sx = plot.left + plot.width * (s.t - x0) / span;

    canvas.drawLine(
      Offset(sx, plot.top),
      Offset(sx, plot.bottom),
      Paint()
        ..color = tooltipTextColor.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    for (final m in metrics) {
      final v = m.valueOf(s, system);
      if (v == null) continue;
      final y = plot.bottom -
          plot.height * (v / axisMax[m.unitIn(system)]!).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(sx, y), 4, Paint()..color = m.color);
    }

    TextPainter tp(String text, {bool bold = false}) => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: tooltipTextColor,
              fontSize: 12,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

    final header = tp(_clock(s.t), bold: true);
    final rows = [
      for (final (m, value) in hoverRows(s, metrics, system))
        (m.color, tp(m.label), tp(value, bold: true)),
    ];
    const pad = 8.0, swatch = 10.0, colGap = 12.0, rowGap = 4.0;
    final labelW = rows.fold(0.0, (w, r) => math.max(w, r.$2.width));
    final valueW = rows.fold(0.0, (w, r) => math.max(w, r.$3.width));
    final width = math.max(
        header.width, swatch + 6 + labelW + colGap + valueW) + pad * 2;
    final rowH = header.height;
    final height = pad * 2 + rowH + rows.length * (rowH + rowGap);

    // Right of the line, flipping to the left near the plot's right edge.
    var left = sx + 12;
    if (left + width > plot.right) left = sx - 12 - width;
    left = left.clamp(0.0, math.max(0.0, size.width - width));
    final box = Rect.fromLTWH(left, plot.top + 4, width, height);

    final rrect = RRect.fromRectAndRadius(box, const Radius.circular(6));
    canvas.drawRRect(rrect, Paint()..color = tooltipColor);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = gridColor
        ..style = PaintingStyle.stroke,
    );

    var y = box.top + pad;
    header.paint(canvas, Offset(box.left + pad, y));
    y += rowH + rowGap;
    for (final (color, label, value) in rows) {
      canvas.drawCircle(
          Offset(box.left + pad + swatch / 2, y + rowH / 2), swatch / 2 - 1, Paint()..color = color);
      label.paint(canvas, Offset(box.left + pad + swatch + 6, y));
      value.paint(canvas, Offset(box.right - pad - value.width, y));
      y += rowH + rowGap;
    }
  }

  static double _niceMax(double peak) {
    if (peak <= 0) return 100;
    final raw = peak * 1.05 / _divisions;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final f in const [1, 2, 2.5, 5, 10]) {
      if (raw <= f * mag) return f * mag * _divisions;
    }
    return 10 * mag * _divisions;
  }

  static double _timeStep(double spanSeconds) {
    for (final s in const [15, 30, 60, 120, 300, 600, 900, 1800, 3600]) {
      if (spanSeconds / s <= 6) return s.toDouble();
    }
    return 3600;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  static String _clock(double seconds) {
    final s = seconds.round();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  void _text(Canvas canvas, String text, Offset at,
      {_Align align = _Align.left, double dy = 0}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: textColor, fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      _Align.left => 0.0,
      _Align.center => -tp.width / 2,
      _Align.right => -tp.width,
    };
    // dy == 0 centres on the anchor vertically (axis labels); otherwise it is
    // an offset from the anchor's top.
    final y = dy == 0 ? at.dy - tp.height / 2 : at.dy + dy - tp.height / 2;
    tp.paint(canvas, Offset(at.dx + dx, y));
  }

  @override
  bool shouldRepaint(_RideChartPainter old) => true;
}

enum _Align { left, center, right }

/// A series that can be drawn on the ride chart. Series sharing a [unit]
/// share a y-axis.
enum RideMetric {
  target('ERG target', 'W', Color(0xFFF59E0B), step: true),
  power('Power', 'W', Color(0xFF3B82F6)),
  smoothedPower('Power (3 s)', 'W', Color(0xFF6366F1)),
  cadence('Cadence', 'rpm', Color(0xFF10B981), smoothSeconds: 5),
  speed('Speed', 'km/h', Color(0xFFA855F7), smoothSeconds: 5),
  heartRate('Heart rate', 'bpm', Color(0xFFEF4444));

  const RideMetric(this.label, this.unit, this.color,
      {this.step = false, this.smoothSeconds = 0});

  final String label;
  final String unit;
  final Color color;

  /// Drawn as a staircase (value holds until it changes) instead of a slope.
  final bool step;

  /// The chart draws a moving average over this many seconds (0 = raw).
  /// Tooltips still report the actual reading.
  final double smoothSeconds;

  /// [unit] is the metric unit; only speed changes with [UnitSystem].
  String unitIn(UnitSystem u) => this == RideMetric.speed ? speedUnit(u) : unit;

  /// Value in [units] (default metric, as stored).
  double? valueOf(RideSample s, [UnitSystem units = UnitSystem.metric]) =>
      switch (this) {
        RideMetric.target => s.target?.toDouble(),
        RideMetric.power => s.power?.toDouble(),
        RideMetric.smoothedPower => s.smoothedPower,
        RideMetric.cadence => s.cadence,
        RideMetric.speed => s.speed == null ? null : speedIn(s.speed!, units),
        RideMetric.heartRate => s.heartRate?.toDouble(),
      };
}

/// [values] (one per sample, null where missing) averaged over a window of
/// [seconds] centred on each sample, using only the readings that exist. A
/// [seconds] of 0 returns [values] unchanged. Gaps stay gaps.
List<double?> smoothSeries(
    List<RideSample> samples, List<double?> values, double seconds) {
  if (seconds <= 0) return values;
  final half = seconds / 2;
  final out = <double?>[];
  for (var i = 0; i < samples.length; i++) {
    if (values[i] == null) {
      out.add(null);
      continue;
    }
    var sum = 0.0;
    var n = 0;
    for (var j = i; j >= 0 && samples[i].t - samples[j].t <= half; j--) {
      final v = values[j];
      if (v != null) {
        sum += v;
        n++;
      }
    }
    for (var j = i + 1;
        j < samples.length && samples[j].t - samples[i].t <= half;
        j++) {
      final v = values[j];
      if (v != null) {
        sum += v;
        n++;
      }
    }
    out.add(sum / n);
  }
  return out;
}

/// Metric toggles (which double as the legend) and, optionally, the
/// time-window picker, in one compact row.
class ChartOptions extends ConsumerWidget {
  const ChartOptions({super.key, required this.settings, this.showWindow = true});

  final ChartSettings settings;
  final bool showWindow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(chartSettingsProvider.notifier);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final m in RideMetric.values)
          _MetricToggle(
            metric: m,
            selected: settings.visible.contains(m),
            onTap: () => c.toggle(m),
          ),
        if (showWindow) _WindowMenu(window: settings.window, onChanged: c.setWindow),
      ],
    );
  }
}

/// A series in the legend that shows or hides it. On is a filled dot and a
/// border in the series colour; off is a hollow dot and a quiet border, so
/// the state never depends on colour alone.
class _MetricToggle extends StatelessWidget {
  const _MetricToggle({
    required this.metric,
    required this.selected,
    required this.onTap,
  });

  final RideMetric metric;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      toggled: selected,
      label: metric.label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? metric.color : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? metric.color : Colors.transparent,
                border: Border.all(color: metric.color, width: 1.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              metric.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ]),
        ),
      ),
      ),
    );
  }
}

/// How much of the ride the live chart shows: all of it, or the last few
/// minutes.
class _WindowMenu extends StatelessWidget {
  const _WindowMenu({required this.window, required this.onChanged});

  final Duration? window;
  final ValueChanged<Duration?> onChanged;

  static const _minutes = [0, 5, 10, 20]; // 0 = the whole ride

  static String _label(int minutes) =>
      minutes == 0 ? 'Whole ride' : 'Last $minutes min';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = window?.inMinutes ?? 0;
    return PopupMenuButton<int>(
      tooltip: 'How much of the ride to show',
      initialValue: current,
      onSelected: (m) => onChanged(m == 0 ? null : Duration(minutes: m)),
      itemBuilder: (_) => [
        for (final m in _minutes)
          PopupMenuItem(value: m, child: Text(_label(m))),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_label(current), style: theme.textTheme.bodySmall),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
      ),
    );
  }
}
