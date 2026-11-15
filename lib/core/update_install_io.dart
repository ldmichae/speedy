import 'dart:io';

import 'package:http/http.dart' as http;

import 'update.dart';

bool get canSelfUpdate => Platform.isWindows;

// Runs after the app exits (a running exe's files are locked): unpack the
// zip, copy it over the install folder, relaunch. Relaunches even on failure
// so the user is never left without an app.
const _script = r'''
param($ProcId, $Zip, $Dir, $Exe)
Wait-Process -Id $ProcId -ErrorAction SilentlyContinue
try {
  $stage = "$Zip.d"
  Expand-Archive -LiteralPath $Zip -DestinationPath $stage -Force
  robocopy $stage $Dir /E /R:10 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
} finally {
  Start-Process $Exe
}
''';

/// Downloads [update], hands the swap to a detached script and exits the app.
Future<void> installUpdate(AppUpdate update) async {
  final res = await http.get(update.zip);
  if (res.statusCode != 200) {
    throw HttpException('Download failed (${res.statusCode})');
  }
  final tmp = await Directory.systemTemp.createTemp('speedy-update');
  final zip = File('${tmp.path}\\update.zip');
  await zip.writeAsBytes(res.bodyBytes);
  final ps1 = File('${tmp.path}\\apply.ps1');
  await ps1.writeAsString(_script);

  final exe = Platform.resolvedExecutable;
  await Process.start(
    'powershell',
    [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
      '-File', ps1.path,
      '$pid', zip.path, File(exe).parent.path, exe,
    ],
    mode: ProcessStartMode.detached,
  );
  exit(0);
}
