import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Saves [bytes] under Documents/IndoorCycling and returns the file path.
Future<String> saveRideFile(Uint8List bytes, String ext, DateTime startedAt) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}IndoorCycling');
  await dir.create(recursive: true);
  String two(int n) => n.toString().padLeft(2, '0');
  final d = startedAt;
  final name = 'ride_${d.year}${two(d.month)}${two(d.day)}_'
      '${two(d.hour)}${two(d.minute)}${two(d.second)}.$ext';
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file.path;
}
