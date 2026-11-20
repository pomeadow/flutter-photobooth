import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/widgets/flash_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opacity of the white overlay, or 0 when it isn't drawn.
double _flashAlpha(WidgetTester tester) {
  final boxes = find.descendant(
    of: find.byType(FlashOverlay),
    matching: find.byType(ColoredBox),
  );
  if (boxes.evaluate().isEmpty) return 0;
  return tester.widget<ColoredBox>(boxes.last).color.a;
}

void main() {
  late FlashController controller;
  late List<String> events;

  Future<void> pumpOverlay(WidgetTester tester, {Duration? fadeOut}) {
    controller = FlashController();
    events = [];
    return tester.pumpWidget(
      MaterialApp(
        home: FlashOverlay(
          controller: controller,
          fadeOut: fadeOut ?? const Duration(milliseconds: 150),
          onStart: () => events.add('start'),
          onEnd: () => events.add('end'),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  testWidgets('holds full white, fades, then disappears at 300 ms', (
    tester,
  ) async {
    await pumpOverlay(tester);
    expect(_flashAlpha(tester), 0);

    var done = false;
    controller.flash().then((_) => done = true);
    await tester.pump(); // start
    expect(controller.isFlashing, isTrue);
    expect(_flashAlpha(tester), 1);

    await tester.pump(const Duration(milliseconds: 140));
    expect(_flashAlpha(tester), 1, reason: 'still in the hold phase');

    await tester.pump(const Duration(milliseconds: 85)); // ≈225 ms
    expect(_flashAlpha(tester), inExclusiveRange(0.2, 0.8));

    await tester.pump(const Duration(milliseconds: 100)); // >300 ms
    await tester.pump();
    expect(_flashAlpha(tester), 0);
    expect(done, isTrue);
    expect(controller.isFlashing, isFalse);
    expect(events, ['start', 'end']);
  });

  testWidgets('fadeOut zero = Python instant on/off', (tester) async {
    await pumpOverlay(tester, fadeOut: Duration.zero);

    controller.flash();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(_flashAlpha(tester), 1);

    await tester.pump(const Duration(milliseconds: 20)); // 160 ms
    await tester.pump();
    expect(_flashAlpha(tester), 0);
  });

  testWidgets('flash() while flashing shares the running flash', (
    tester,
  ) async {
    await pumpOverlay(tester);

    final first = controller.flash();
    await tester.pump(); // first frame starts the animation clock
    await tester.pump(const Duration(milliseconds: 100));
    final second = controller.flash();
    expect(identical(first, second), isTrue);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(); // onEnd runs after the animation's future completes
    expect(events, ['start', 'end']);
  });

  testWidgets('overlay does not block taps on the child', (tester) async {
    controller = FlashController();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FlashOverlay(
          controller: controller,
          child: GestureDetector(
            // Opaque: an empty SizedBox isn't hit-testable by itself.
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    controller.flash();
    await tester.pump();
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
