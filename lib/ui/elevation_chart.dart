import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/elevation.dart';
import '../core/units.dart';
import 'units_controller.dart';

/// Elevation over distance as a filled area, with an optional marker at
/// [riderMeters]. Under 80 px tall it is shape only (a thumbnail).
class ElevationChart extends ConsumerWidget {
  const ElevationChart(
      {super.key,
      required this.profile,
      this.height = 80,
      this.riderMeters,
      this.yMin,
      this.yMax});

  final ElevationProfile profile;
  final double height;
  final double? riderMeters;

  /// Fixed height range, so charts side by side share one scale.
  final double? yMin, yMax;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(rideUnitsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Elevation profile, ${elevationText(profile.climb, units)} of climbing',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
            painter: _ElevationPainter(profile, riderMeters, scheme.tertiary,
                scheme.onSurfaceVariant, yMin, yMax, units)),
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter(
      this.p, this.rider, this.color, this.textColor, this.yMin, this.yMax,
      this.units);
  final UnitSystem units;
  final double? yMin, yMax;
  final ElevationProfile p;
  final double? rider;
  final Color color, textColor;

  void _text(Canvas c, String s, Offset at,
      {bool right = false, bool bottom = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: textColor, fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        c,
        Offset(
            at.dx - (right ? tp.width : 0), at.dy - (bottom ? tp.height : 0)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final small = size.height < 80;
    final top = small ? 3.0 : 14.0, bottom = small ? 3.0 : 14.0;
    final lo = yMin ?? p.minElevation, hi = yMax ?? p.maxElevation;
    // At least 20 m of vertical range so a flat route doesn't look alpine.
    final range = (hi - lo) < 20 ? 20.0 : hi - lo;
    final base = (hi - lo) < 20 ? (lo + hi) / 2 - 10 : lo;
    final len = p.lengthMeters == 0 ? 1.0 : p.lengthMeters;
    Offset at(double d, double e) => Offset(
        size.width * d / len,
        size.height -
            bottom -
            (size.height - top - bottom) * (e - base) / range);

    final line = Path()
      ..moveTo(at(p.distances.first, p.elevations.first).dx,
          at(p.distances.first, p.elevations.first).dy);
    for (var i = 1; i < p.distances.length; i++) {
      final o = at(p.distances[i], p.elevations[i]);
      line.lineTo(o.dx, o.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height - bottom)
      ..lineTo(0, size.height - bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.28));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);

    final r = rider;
    if (r != null) {
      final m = at(r, p.elevationAt(r));
      canvas.drawLine(
          Offset(m.dx, top),
          Offset(m.dx, size.height - bottom),
          Paint()
            ..color = const Color(0xFF2563EB)
            ..strokeWidth = 1.5);
      canvas.drawCircle(m, 5, Paint()..color = Colors.white);
      canvas.drawCircle(m, 3.5, Paint()..color = const Color(0xFF2563EB));
    }

    if (small) return;
    _text(canvas, elevationText(hi, units), Offset.zero);
    _text(canvas, elevationText(lo, units), Offset(0, size.height),
        bottom: true);
  }

  @override
  bool shouldRepaint(_ElevationPainter old) => true;
}
