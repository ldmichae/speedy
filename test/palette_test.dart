import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/ui/app_palette.dart';
import 'package:indoor_cycling/ui/preferences_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every palette is a dark Material 3 scheme with its own primary', () {
    final primaries = <Color>{};
    for (final p in AppPalette.values) {
      final t = p.theme;
      expect(t.useMaterial3, isTrue);
      expect(t.colorScheme.brightness, Brightness.dark);
      primaries.add(t.colorScheme.primary);
    }
    expect(primaries, hasLength(AppPalette.values.length));
  });

  testWidgets('picking a colour changes the theme and is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: ref.watch(paletteProvider).theme,
          home: const PreferencesScreen(),
        ),
      ),
    ));

    await tester.tap(find.text('Orange'));
    await tester.pumpAndSettle();

    expect(container.read(paletteProvider), AppPalette.orange);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary,
        AppPalette.orange.theme.colorScheme.primary);
    expect((await SharedPreferences.getInstance()).getString('appPalette'),
        'orange');
  });

  test('a stored palette is restored', () async {
    SharedPreferences.setMockInitialValues({'appPalette': 'purple'});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(paletteProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(paletteProvider), AppPalette.purple);
  });
}
