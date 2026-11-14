import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import 'elevation.dart';
import 'route.dart';

/// Turns GPX text into a route (track points, else route points). Elevation
/// is kept when every point has one. Throws [FormatException] if unusable.
///
/// shortcut: waypoints are just the two ends, so editing a GPX route and
/// adding a point re-snaps the whole thing; upgrade if that bites.
SavedRoute parseGpx(String text, {String fallbackName = 'Imported route'}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw FormatException('Not a valid GPX file: ${e.message}');
  }
  var els = doc.findAllElements('trkpt').toList();
  if (els.isEmpty) els = doc.findAllElements('rtept').toList();
  final pts = <LatLng>[];
  final eles = <double?>[];
  for (final e in els) {
    final lat = double.tryParse(e.getAttribute('lat') ?? '');
    final lon = double.tryParse(e.getAttribute('lon') ?? '');
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      throw const FormatException('GPX has an invalid point.');
    }
    pts.add(LatLng(lat, lon));
    eles.add(double.tryParse(e.getElement('ele')?.innerText.trim() ?? ''));
  }
  if (pts.length < 2) throw const FormatException('GPX has no track to ride.');

  final name = (doc.findAllElements('trk').firstOrNull ??
          doc.findAllElements('rte').firstOrNull)
      ?.getElement('name')
      ?.innerText
      .trim();
  final path = simplifyPath(pts);
  final route = SavedRoute(name == null || name.isEmpty ? fallbackName : name,
      [pts.first, pts.last], path);
  if (eles.any((e) => e == null)) return route;

  // Heights are along the original points; resample every ~50 m, scaled to
  // the simplified path's length so the profile matches the stored route.
  final d = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    d.add(d.last + pathLength([pts[i - 1], pts[i]]));
  }
  if (d.last <= 0) return route;
  final raw = ElevationProfile.fromSamples(d, [for (final e in eles) e!]);
  final n = (d.last / 50).ceil().clamp(1, 1 << 20) + 1;
  final scale = route.lengthMeters / d.last;
  return route.withElevation(ElevationProfile.fromSamples([
    for (var i = 0; i < n; i++) d.last * i / (n - 1) * scale
  ], [
    for (var i = 0; i < n; i++) raw.elevationAt(d.last * i / (n - 1))
  ]));
}
