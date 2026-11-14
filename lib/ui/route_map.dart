import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/route_service.dart' show appUserAgent;

/// One place to change where map tiles come from. The public OSM server is
/// for light use only (see its tile usage policy); swap this for a keyed
/// provider if the app ever grows past a rider or two.
const tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Zoom range we allow. OSM serves up to 19; closer than that is just more
/// requests, and the whole-world view is not useful for planning rides.
const minMapZoom = 3.0, maxMapZoom = 18.0;

/// Overridable so tests do not fetch tiles.
///
/// Good-citizen settings for the public OSM server: an identifying
/// User-Agent (native; browsers set their own and send a Referer), no
/// automatic retries (flutter_map's default client retries failures), the
/// built-in disk cache that honours the server's cache headers, and
/// cancelling requests for tiles that scrolled away.
final tileProviderProvider = Provider<TileProvider>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return NetworkTileProvider(
    httpClient: client,
    headers: {if (!kIsWeb) 'User-Agent': appUserAgent},
    abortObsoleteRequests: true,
  );
});

/// Tiles plus the attribution OSM and the FOSSGIS router require.
/// [panBuffer] is how many extra rings of tiles to load around the view:
/// 0 where the map barely moves (the ride tile), 1 where you pan (the editor).
List<Widget> mapBaseLayers(WidgetRef ref, {int panBuffer = 1}) => [
      TileLayer(
        urlTemplate: tileUrlTemplate,
        userAgentPackageName: 'indoor_cycling',
        tileProvider: ref.watch(tileProviderProvider),
        maxNativeZoom: 19,
        panBuffer: panBuffer,
      ),
      // OSM's policy: the credit must be visible on the map, not behind a
      // toggle. The other credits can live in the expandable box.
      const _OsmCredit(),
      const RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        showFlutterMapAttribution: false,
        attributions: [
          TextSourceAttribution('© OpenStreetMap contributors'),
          TextSourceAttribution('Routing: FOSSGIS OSRM'),
          TextSourceAttribution('Elevation: AWS Terrain Tiles, Open-Meteo'),
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

/// "© OpenStreetMap contributors", always visible at the bottom right of the
/// map (OSM's policy forbids hiding it behind a toggle). Shrinks and clips
/// rather than overflowing on a narrow tile.
class _OsmCredit extends StatelessWidget {
  const _OsmCredit();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              '© OpenStreetMap contributors',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}
