import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/widgets/badge_label.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('counter text matches Python format', (tester) async {
    await tester.pumpWidget(_wrap(BadgeLabel.counter(taken: 1, total: 4)));
    expect(find.text('Photos: 1 / 4'), findsOneWidget);
  });

  testWidgets('timer shows seconds, or "Time\'s up!" when null', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(BadgeLabel.timer(seconds: 5)));
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(_wrap(BadgeLabel.timer(seconds: null)));
    expect(find.text("Time's up!"), findsOneWidget);
  });

  for (final seconds in [3, 10]) {
    testWidgets('timer showing $seconds is a circle (width == height)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(BadgeLabel.timer(seconds: seconds)));
      final size = tester.getSize(find.byType(BadgeLabel));
      expect(size.width, size.height);
    });
  }

  testWidgets('"Time\'s up!" timer is a pill (wider than tall)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(BadgeLabel.timer(seconds: null)));
    final size = tester.getSize(find.byType(BadgeLabel));
    expect(size.width, greaterThan(size.height));
  });

  testWidgets('badges hug content instead of filling the parent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(BadgeLabel.timer(seconds: null)));
    final size = tester.getSize(find.byType(BadgeLabel));
    expect(size.width, lessThan(1920));
    expect(size.height, lessThan(1080));
  });
}
