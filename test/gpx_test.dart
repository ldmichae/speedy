import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/gpx.dart';
import 'package:indoor_cycling/core/route.dart';

String gpx(String pts, {String name = '<name>Loop</name>'}) =>
    '<gpx><trk>$name<trkseg>$pts</trkseg></trk></gpx>';

void main() {
  _split();
  _splitAt();
  test('parses a track with elevation', () {
    final r = parseGpx(gpx('<trkpt lat="48" lon="10"><ele>100</ele></trkpt>'
        '<trkpt lat="48.01" lon="10"><ele>150</ele></trkpt>'));
    expect(r.name, 'Loop');
    expect(r.lengthMeters, closeTo(1112, 5));
    expect(r.elevation!.climb, closeTo(50, 1));
    expect(r.elevation!.lengthMeters, closeTo(r.lengthMeters, 1));
  });

  test('no elevation when a point lacks it; falls back to file name', () {
    final r = parseGpx(
        gpx('<trkpt lat="48" lon="10"/><trkpt lat="48.01" lon="10"/>', name: ''),
        fallbackName: 'ride');
    expect(r.elevation, isNull);
    expect(r.name, 'ride');
  });

  test('rejects junk', () {
    expect(() => parseGpx('nope'), throwsFormatException);
    expect(() => parseGpx(gpx('<trkpt lat="48" lon="10"/>')), throwsFormatException);
    expect(() => parseGpx(gpx('<trkpt lat="99" lon="10"/><trkpt lat="1" lon="1"/>')),
        throwsFormatException);
  });
}

void _split() {
  test('splitInto makes equal stages that add up to the route', () {
    final r = parseGpx(gpx('<trkpt lat="48" lon="10"><ele>100</ele></trkpt>'
        '<trkpt lat="48.05" lon="10"><ele>200</ele></trkpt>'));
    final s = r.splitInto(2000); // ~5.5 km -> 3 stages
    expect(s.length, 3);
    expect(s.fold(0.0, (a, x) => a + x.lengthMeters),
        closeTo(r.lengthMeters, 1));
    expect(s.fold(0.0, (a, x) => a + x.elevation!.climb), closeTo(100, 2));
    expect(s[1].path.first.latitude, closeTo(s[0].path.last.latitude, 1e-9));
  });
}

void _splitAt() {
  test('splitAt cuts where asked', () {
    final r = parseGpx(gpx('<trkpt lat="48" lon="10"/><trkpt lat="48.05" lon="10"/>'));
    final s = r.splitAt([3000, 1000]);
    expect([for (final x in s) x.lengthMeters.round()],
        [1000, 2000, r.lengthMeters.round() - 3000]);
  });
}
