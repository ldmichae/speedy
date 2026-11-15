import 'dart:convert';

import 'package:http/http.dart' as http;

import 'route_service.dart' show appUserAgent;

export 'update_install_stub.dart'
    if (dart.library.io) 'update_install_io.dart';

/// A GitHub release newer than the running app, with its Windows zip.
class AppUpdate {
  const AppUpdate(this.version, this.zip);
  final String version;
  final Uri zip;
}

const _latestRelease =
    'https://api.github.com/repos/ldmichae/speedy/releases/latest';

/// Reads a GitHub "latest release" payload: the tag (`v0.3.1`) and its
/// `-windows.zip` asset. Null when the release has no such asset.
AppUpdate? parseRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  if (tag is! String) return null;
  for (final a in (json['assets'] as List? ?? const [])) {
    final name = a['name'];
    final url = a['browser_download_url'];
    if (name is String && url is String && name.endsWith('-windows.zip')) {
      return AppUpdate(tag.replaceFirst('v', ''), Uri.parse(url));
    }
  }
  return null;
}

/// True when [latest] is a higher x.y.z than [current] (`+build` ignored).
bool isNewer(String latest, String current) {
  List<int> parts(String v) => [
        for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0
      ];
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The newer release than [current], or null if up to date. Throws on
/// network errors.
Future<AppUpdate?> checkForUpdate(String current, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(Uri.parse(_latestRelease),
        headers: {'User-Agent': appUserAgent});
    if (res.statusCode != 200) return null;
    final u = parseRelease(jsonDecode(res.body) as Map<String, dynamic>);
    return u != null && isNewer(u.version, current) ? u : null;
  } finally {
    if (client == null) c.close();
  }
}
