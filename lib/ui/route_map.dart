import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// One place to change where map tiles come from. The public OSM server is
/// for light use only (see its tile usage policy); swap this for a keyed
/// provider if the app ever grows past a rider or two.
const tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Overridable so tests do not fetch tiles.
final tileProviderProvider = Provider<TileProvider>((ref) => NetworkTileProvider());

/// Tiles plus the attribution OSM and the FOSSGIS router require.
List<Widget> mapBaseLayers(WidgetRef ref) => [
      TileLayer(
        urlTemplate: tileUrlTemplate,
        userAgentPackageName: 'com.example.indoor_cycling',
        tileProvider: ref.watch(tileProviderProvider),
      ),
      const RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        attributions: [
          TextSourceAttribution('© OpenStreetMap contributors'),
          TextSourceAttribution('Routing: FOSSGIS OSRM'),
        ],
      ),
    ];

/// The blue "you are here" dot.
Marker riderMarker(LatLng at) => Marker(
      point: at,
      width: 22,
      height: 22,
      child: DecoratedBox(
        key: const Key('riderDot'),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black45)],
        ),
      ),
    );

Polyline routeLine(List<LatLng> path, {double width = 5}) => Polyline(
      points: path,
      strokeWidth: width,
      color: const Color(0xFFF59E0B),
      borderStrokeWidth: 1.5,
      borderColor: Colors.white,
    );
