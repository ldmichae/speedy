import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/core/route_service.dart';
import 'package:indoor_cycling/ui/route_map.dart';

void main() {
  test('tile requests identify the app and are limited to a sane zoom range', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final p = c.read(tileProviderProvider);
    if (!kIsWeb) expect(p.headers['User-Agent'], appUserAgent);
    expect(appUserAgent, contains('indoor-cycling-app'));
    expect(appUserAgent, contains('github.com'));
    expect(maxMapZoom, lessThanOrEqualTo(19));
  });
}
