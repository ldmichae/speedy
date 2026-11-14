import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/gpx.dart';

String gpx(String pts, {String name = '<name>Loop</name>'}) =>
    '<gpx><trk>$name<trkseg>$pts</trkseg></trk></gpx>';

void main() {
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
