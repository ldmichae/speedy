import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/ui/route_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('the OSM credit is visible on the map without opening anything',
      (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => FlutterMap(
            options: const MapOptions(initialCenter: LatLng(0, 0), initialZoom: 3),
            children: mapBaseLayers(ref),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(find.textContaining('OpenStreetMap contributors'), findsWidgets);
    expect(find.text('© OpenStreetMap contributors'), findsWidgets);
  });
}
