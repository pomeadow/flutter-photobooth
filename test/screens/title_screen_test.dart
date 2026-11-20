import 'package:flutter_photobooth/screens/title_screen.dart';
import 'package:flutter_photobooth/widgets/decorative_button.dart';
import 'package:flutter_photobooth/widgets/design_canvas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 1;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first
        .reset();
  });

  testWidgets('tapping START calls onStart', (tester) async {
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(home: TitleScreen(onStart: () => starts++)),
    );
    await tester.tap(find.text('START'));
    expect(starts, 1);
  });

  testWidgets('uses the solid background', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TitleScreen(onStart: () {})));
    expect(
      tester.widget<DesignCanvas>(find.byType(DesignCanvas)).background,
      AppBackgrounds.solid,
    );
  });

  testWidgets('START sits bottom-centre, 80 px above the bottom', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: TitleScreen(onStart: () {})));
    final button = tester.getRect(find.byType(DecorativeButton));
    expect(button.size, const Size(800, 120));
    expect(button.center.dx, closeTo(960, 0.5));
    expect(button.bottom, closeTo(1080 - 80, 0.5));
  });

  testWidgets('null onStart disables START', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TitleScreen(onStart: null)),
    );
    await tester.tap(find.text('START'), warnIfMissed: false);
    expect(find.byType(Opacity), findsOneWidget);
  });
}
