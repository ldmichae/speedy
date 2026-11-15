import 'update.dart';

/// Only the Windows build can replace itself.
bool get canSelfUpdate => false;

Future<void> installUpdate(AppUpdate update) async =>
    throw UnsupportedError('Updating in place is only supported on Windows.');
