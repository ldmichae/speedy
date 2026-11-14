import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indoor_cycling/core/elevation.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:latlong2/latlong.dart';

// 1 km, flat for 500 m then 10% for 500 m (raw, before smoothing).
ElevationProfile ramp() => ElevationProfile.fromSamples(
    [for (var i = 0; i <= 20; i++) i * 50.0],
    [for (var i = 0; i <= 20; i++) i <= 10 ? 0.0 : (i - 10) * 5.0]);

final route = SavedRoute('R', const [LatLng(0, 0), LatLng(0.009, 0)],
    const [LatLng(0, 0), LatLng(0.009, 0)]); // ~1 km

void main() {
  test('climb, descent, elevationAt and gradeAt', () {
    final p = ramp();
    expect(p.climb, closeTo(50, 4));
    expect(p.descent, closeTo(0, 1e-9));
    expect(p.elevationAt(-10), p.elevations.first);
    expect(p.elevationAt(1e6), p.elevations.last);
    expect(p.gradeAt(0, span: 150), closeTo(0, 0.5));
    expect(p.gradeAt(800, span: 150), closeTo(10, 1));
    expect(p.gradeAt(5000, span: 150), closeTo(10, 1)); // clamps to the end
    expect(p.gradeRange.$1, closeTo(10, 1));
  });

  test('json round-trips; junk gives no profile', () {
    final back = ElevationProfile.fromJson(ramp().toJson())!;
    expect(back.lengthMeters, 1000);
    expect(ElevationProfile.fromJson({'d': [0, 1], 'e': [1]}), isNull);
    expect(ElevationProfile.fromJson({'d': [5, 1], 'e': [1, 2]}), isNull);
    expect(ElevationProfile.fromJson('x'), isNull);
  });

  test('a route keeps its profile through json; old routes still load', () {
    final r = route.withElevation(ramp());
    expect(SavedRoute.fromJson(r.toJson())!.elevation, isNotNull);
    expect(SavedRoute.fromJson(route.toJson())!.elevation, isNull);
  });

  test('samplePoints spaces points and keeps the end', () {
    final s = samplePoints(route);
    expect(s.first.$1, 0);
    expect(s.last.$1, closeTo(route.lengthMeters, 1e-6));
    expect(s.length, closeTo(route.lengthMeters / 50 + 2, 2));
    expect(samplePoints(route, maxPoints: 10).length, lessThanOrEqualTo(12));
  });

  test('OpenMeteoElevation batches 100 points and returns them in order', () async {
    final sizes = <int>[];
    final src = OpenMeteoElevation(
      gap: const Duration(milliseconds: 1),
      client: MockClient((req) async {
        final n = req.url.queryParameters['latitude']!.split(',').length;
        sizes.add(n);
        return http.Response('{"elevation":[${List.filled(n, 7).join(',')}]}', 200);
      }),
    );
    final out = await src.elevations([for (var i = 0; i < 250; i++) LatLng(i / 1000, 0)]);
    expect(sizes, [100, 100, 50]);
    expect(out.length, 250);
  });

  test('a bad elevation response throws', () async {
    final src = OpenMeteoElevation(
      client: MockClient((_) async => http.Response('{"elevation":[1]}', 200)),
    );
    expect(src.elevations([const LatLng(0, 0), const LatLng(1, 1)]), throwsFormatException);
  });
}
