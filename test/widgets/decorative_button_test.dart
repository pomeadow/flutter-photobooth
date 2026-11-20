import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/widgets/decorative_button.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('tapping calls onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(DecorativeButton(label: 'START', onPressed: () => taps++)),
    );

    await tester.tap(find.text('START'));
    expect(taps, 1);
  });

  testWidgets('hugs its 800×120 minimum instead of filling the parent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(DecorativeButton(label: 'GO', onPressed: () {})),
    );

    expect(tester.getSize(find.byType(DecorativeButton)), const Size(800, 120));
  });

  testWidgets('disabled button ignores taps and is dimmed', (tester) async {
    await tester.pumpWidget(
      _wrap(const DecorativeButton(label: 'START', onPressed: null)),
    );

    await tester.tap(find.text('START'), warnIfMissed: false);
    expect(find.byType(Opacity), findsOneWidget);
  });
}
