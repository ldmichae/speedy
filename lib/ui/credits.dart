import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link in the system browser; false if it could not. Overridable so
/// tests never launch anything.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
    (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

/// Who the map, route and elevation data come from, and where their terms
/// say credit goes. (OSM asks for a link to its copyright page.)
const credits = <({String name, String what, String url})>[
  (
    name: '© OpenStreetMap contributors',
    what: 'Map tiles and the road data behind routing',
    url: 'https://www.openstreetmap.org/copyright',
  ),
  (
    name: 'FOSSGIS OSRM',
    what: 'Road routing between the points you click',
    url: 'https://routing.openstreetmap.de/about.html',
  ),
  (
    name: 'AWS Terrain Tiles',
    what: 'Elevation from terrain tiles (SRTM, NED and other sources)',
    url: 'https://github.com/tilezen/joerd/blob/master/docs/attribution.md',
  ),
  (
    name: 'Open-Meteo',
    what: 'Elevation lookups when terrain tiles are not available',
    url: 'https://open-meteo.com/',
  ),
];

/// One row per credit; tapping opens its page.
class CreditsList extends ConsumerWidget {
  const CreditsList({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await ref.read(urlOpenerProvider)(Uri.parse(url));
    } catch (_) {}
    if (!ok) messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final c in credits)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(c.name),
          subtitle: Text(c.what),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _open(context, ref, c.url),
        ),
    ]);
  }
}
