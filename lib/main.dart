import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app_palette.dart';
import 'ui/home_screen.dart';

void main() => runApp(const ProviderScope(child: IndoorCyclingApp()));

class IndoorCyclingApp extends ConsumerWidget {
  const IndoorCyclingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Indoor Cycling',
      debugShowCheckedModeBanner: false,
      theme: ref.watch(paletteProvider).lightTheme,
      darkTheme: ref.watch(paletteProvider).theme,
      themeMode: ref.watch(themeModeProvider),
      home: const HomeScreen(),
    );
  }
}
