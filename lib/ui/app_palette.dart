import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';

/// Primary colour choices for the app shell. Each is a Material 3 seed: the
/// full tonal palette (primary, secondary, surfaces, containers) is derived by
/// [ColorScheme.fromSeed], so every choice stays within the standard roles.
enum AppPalette {
  teal('Teal', Color(0xFF1FB5A0)),
  blue('Blue', Color(0xFF2196F3)),
  green('Green', Color(0xFF4CAF50)),
  orange('Orange', Color(0xFFFF9800)),
  red('Red', Color(0xFFF44336)),
  pink('Pink', Color(0xFFE91E63)),
  purple('Purple', Color(0xFF9C27B0));

  const AppPalette(this.label, this.seed);
  final String label;
  final Color seed;

  ThemeData get theme => _theme(Brightness.dark);
  ThemeData get lightTheme => _theme(Brightness.light);

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: b),
      );
}

/// Dark by default (the look so far); System or Light for a bright room.
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends PersistedNotifier<ThemeMode> {
  @override
  ThemeMode get defaults => ThemeMode.dark;

  @override
  ThemeMode? read(SharedPreferences p) {
    final name = p.getString('themeMode');
    return ThemeMode.values.where((x) => x.name == name).firstOrNull;
  }

  @override
  Future<void> write(SharedPreferences p, ThemeMode v) =>
      p.setString('themeMode', v.name);

  void set(ThemeMode m) => put(m);
}

class ThemeModeChooser extends ConsumerWidget {
  const ThemeModeChooser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ButtonSegment(value: ThemeMode.light, label: Text('Light')),
          ButtonSegment(value: ThemeMode.system, label: Text('System')),
        ],
        selected: {ref.watch(themeModeProvider)},
        onSelectionChanged: (s) =>
            ref.read(themeModeProvider.notifier).set(s.first),
      );
}

final paletteProvider =
    NotifierProvider<PaletteController, AppPalette>(PaletteController.new);

class PaletteController extends PersistedNotifier<AppPalette> {
  static const _key = 'appPalette';

  @override
  AppPalette get defaults => AppPalette.teal;

  @override
  AppPalette? read(SharedPreferences p) {
    final name = p.getString(_key);
    return AppPalette.values.where((x) => x.name == name).firstOrNull;
  }

  @override
  Future<void> write(SharedPreferences p, AppPalette v) =>
      p.setString(_key, v.name);

  void set(AppPalette p) => put(p);
}

/// The colour swatches; selecting one applies and saves it immediately.
class PaletteChooser extends ConsumerWidget {
  const PaletteChooser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(paletteProvider);
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final p in AppPalette.values)
          Semantics(
            button: true,
            selected: p == current,
            label: p.label,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => ref.read(paletteProvider.notifier).set(p),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: p.seed,
                  child: p == current
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 4),
                Text(p.label, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
      ],
    );
  }
}
