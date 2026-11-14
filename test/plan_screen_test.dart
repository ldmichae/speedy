import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indoor_cycling/ui/plan_screen.dart';

void main() {
  Future<void> open(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
        const ProviderScope(child: MaterialApp(home: PlanEditor())));
  }

  int seconds(WidgetTester t) => (t.widget(find.byType(PlanPreview)) as PlanPreview)
      .steps
      .fold(0, (a, s) => a + s.seconds);

  testWidgets('the chart follows the fields and stays put while blocks scroll',
      (t) async {
    await open(t, const Size(600, 800));
    expect(seconds(t), 300);

    await t.enterText(find.widgetWithText(TextField, 'Minutes').first, '10');
    await t.pump();
    expect(seconds(t), 600);

    for (var i = 0; i < 12; i++) {
      await t.tap(find.text('Add block'));
      await t.pump();
      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pump();
    }
    expect(find.byType(PlanPreview).hitTestable(), findsOneWidget);
    expect(t.getTopLeft(find.byType(PlanPreview)).dy, lessThan(300));
  });

  testWidgets('wide windows put the chart on the right', (t) async {
    await open(t, const Size(1400, 800));
    expect(t.getTopLeft(find.byType(PlanPreview)).dx, greaterThan(800));
  });
}
