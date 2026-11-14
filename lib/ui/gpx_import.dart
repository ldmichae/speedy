import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/gpx.dart';
import '../core/route.dart';

/// Asks for a .gpx file and parses it; null if cancelled. Problems are shown
/// in a snackbar.
Future<SavedRoute?> pickGpxRoute(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['gpx']);
    if (file == null) return null;
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    return parseGpx(text,
        fallbackName:
            file.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), ''));
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger
        .showSnackBar(const SnackBar(content: Text('Could not import that file.')));
  }
  return null;
}
