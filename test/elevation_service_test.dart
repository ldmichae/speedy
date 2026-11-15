import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/elevation.dart';
import 'package:indoor_cycling/core/route.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:indoor_cycling/ui/elevation_service.dart';
import 'package:latlong2/latlong.dart';

class _Source extends ElevationSource {
  _Source(this.fail);
  Object? fail;
  int calls = 0;

  @override
  Future<List<double>> elevations(List<LatLng> points) async {
    calls++;
    if (fail != null) throw fail!;
    return [for (final _ in points) 10.0];
  }
}

void main() {
  final route = SavedRoute('R', const [LatLng(0, 0), LatLng(0.009, 0)],
      const [LatLng(0, 0), LatLng(0.009, 0)]);

  test('a rate limit blocks later lookups without asking the source', () async {
    final src = _Source(ElevationRateLimited(const Duration(minutes: 2)));
    final s = ElevationService(src);

    await expectLater(s.profile(route), throwsA(isA<ElevationRateLimited>()));
    expect(s.blockedFor, isNotNull);

    src.fail = null;
    await expectLater(s.profile(route), throwsA(isA<ElevationRateLimited>()));
    expect(src.calls, 1); // the second lookup never reached the source
  });

  test('other failures do not block', () async {
    final src = _Source(StateError('offline'));
    final s = ElevationService(src);
    await expectLater(s.profile(route), throwsA(isA<StateError>()));
    expect(s.blockedFor, isNull);
    src.fail = null;
    expect(await s.profile(route), isA<ElevationProfile>());
  });
}
