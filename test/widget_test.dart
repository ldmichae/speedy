import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/main.dart';

void main() {
  testWidgets('connects to the simulated trainer and shows live data',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: IndoorCyclingApp()));
    expect(find.text('Connect your trainer'), findsOneWidget);

    await tester.tap(find.text('Use simulated trainer'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('ERG target'), findsOneWidget);

    await tester.tap(find.byTooltip('View and trainer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Connect your trainer'), findsOneWidget);
  });
}
