import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/widgets/selectable_image.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

const _photo = AssetImage('assets/swatches/swatch_vertical_01.png');

bool _hasForegroundBorder(WidgetTester tester, Type type) {
  final container = tester.widget<Container>(
    find.descendant(of: find.byType(type), matching: find.byType(Container)),
  );
  return container.foregroundDecoration != null;
}

void main() {
  group('SelectableImage', () {
    testWidgets('is 300×225 and taps call onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          SelectableImage(image: _photo, selected: false, onTap: () => taps++),
        ),
      );

      expect(
        tester.getSize(find.byType(SelectableImage)),
        const Size(300, 225),
      );
      await tester.tap(find.byType(SelectableImage));
      expect(taps, 1);
    });

    testWidgets('gold border only when selected', (tester) async {
      await tester.pumpWidget(
        _wrap(SelectableImage(image: _photo, selected: false, onTap: () {})),
      );
      expect(_hasForegroundBorder(tester, SelectableImage), isFalse);

      await tester.pumpWidget(
        _wrap(SelectableImage(image: _photo, selected: true, onTap: () {})),
      );
      expect(_hasForegroundBorder(tester, SelectableImage), isTrue);
    });
  });

  group('FrameSwatch', () {
    testWidgets('is a 60 px circle, taps call onTap, ring when selected', (
      tester,
    ) async {
      var taps = 0;
      Widget swatch(bool selected) => _wrap(
        FrameSwatch(
          swatch: 'assets/swatches/swatch_horizontal_01.png',
          fallbackColor: Colors.blue,
          selected: selected,
          onTap: () => taps++,
        ),
      );

      await tester.pumpWidget(swatch(false));
      expect(tester.getSize(find.byType(FrameSwatch)), const Size(60, 60));
      expect(_hasForegroundBorder(tester, FrameSwatch), isFalse);

      await tester.tap(find.byType(FrameSwatch));
      expect(taps, 1);

      await tester.pumpWidget(swatch(true));
      expect(_hasForegroundBorder(tester, FrameSwatch), isTrue);
    });

    testWidgets('missing swatch file falls back to the plain colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FrameSwatch(
            swatch: 'assets/swatches/does_not_exist.png',
            fallbackColor: Colors.green,
            selected: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final box = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(FrameSwatch),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(box.color, Colors.green);
    });
  });
}
