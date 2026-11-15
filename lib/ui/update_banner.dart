import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/update.dart';

/// A newer release, checked once at startup. Null in debug builds (the
/// version there is meaningless), on non-Windows, and when offline.
final updateProvider = FutureProvider<AppUpdate?>((ref) async {
  if (!kReleaseMode || !canSelfUpdate) return null;
  try {
    return await checkForUpdate((await PackageInfo.fromPlatform()).version);
  } catch (_) {
    return null; // an update check must never get in the rider's way
  }
});

/// An update found by the Preferences "Check for updates" button; the banner
/// shows it just like the startup one.
final foundUpdateProvider = StateProvider<AppUpdate?>((ref) => null);

/// "Version X is available" with a one-click install, above the page.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  bool _busy = false;
  String? _error;

  Future<void> _install(AppUpdate u) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await installUpdate(u);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Update failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(foundUpdateProvider) ??
        ref.watch(updateProvider).valueOrNull;
    if (u == null || !canSelfUpdate) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(
            child: Text(
              _error ??
                  (_busy
                      ? 'Downloading ${u.version}… the app will restart.'
                      : 'Version ${u.version} is available. '
                          'Updating restarts the app.'),
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          if (_busy)
            const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            TextButton(
              onPressed: () => _install(u),
              child: Text(_error == null ? 'Update now' : 'Retry'),
            ),
        ]),
      ),
    );
  }
}

/// Preferences row: a manual update check and its result.
class UpdateCheckButton extends ConsumerStatefulWidget {
  const UpdateCheckButton({super.key});

  @override
  ConsumerState<UpdateCheckButton> createState() => _UpdateCheckButtonState();
}

class _UpdateCheckButtonState extends ConsumerState<UpdateCheckButton> {
  bool _busy = false;
  String? _result;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    String result;
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final u = await checkForUpdate(current);
      ref.read(foundUpdateProvider.notifier).state = u;
      result = u == null
          ? 'You are up to date (version $current).'
          : canSelfUpdate
              ? 'Version ${u.version} is available.'
              : 'Version ${u.version} is available on GitHub.';
    } catch (_) {
      result = 'Could not check for updates.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      FilledButton.tonal(
        onPressed: _busy ? null : _check,
        child: const Text('Check for updates'),
      ),
      if (_result != null) ...[
        const SizedBox(width: 16),
        Expanded(child: Text(_result!, key: const Key('updateResult'))),
      ],
    ]);
  }
}
