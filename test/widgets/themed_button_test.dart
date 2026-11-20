import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/theme/app_theme.dart';
import 'package:flutter_photobooth/widgets/themed_button.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

Color? _bg(WidgetTester tester, Set<WidgetState> states) => tester
    .widget<TextButton>(find.byType(TextButton))
    .style!
    .backgroundColor!
    .resolve(states);

void main() {
  testWidgets('tapping calls onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(ThemedButton(label: 'Next', onPressed: () => taps++)),
    );

    await tester.tap(find.text('Next'));
    expect(taps, 1);
  });

  testWidgets('state colours match py-photobooth buttons_css', (tester) async {
    await tester.pumpWidget(_wrap(ThemedButton(label: 'X', onPressed: () {})));

    expect(_bg(tester, {}), AppColors.red);
    expect(_bg(tester, {WidgetState.hovered}), AppColors.redHover);
    expect(_bg(tester, {WidgetState.pressed}), AppColors.redPressed);
  });

  testWidgets('disabled button ignores taps', (tester) async {
    await tester.pumpWidget(
      _wrap(const ThemedButton(label: 'Next', onPressed: null)),
    );

    await tester.tap(find.text('Next'), warnIfMissed: false);
    expect(tester.widget<TextButton>(find.byType(TextButton)).enabled, isFalse);
  });

  testWidgets('compact is smaller than regular', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThemedButton(key: const Key('r'), label: 'Go', onPressed: () {}),
            ThemedButton(
              key: const Key('c'),
              label: 'Go',
              onPressed: () {},
              size: ThemedButtonSize.compact,
            ),
          ],
        ),
      ),
    );

    final regular = tester.getSize(find.byKey(const Key('r')));
    final compact = tester.getSize(find.byKey(const Key('c')));
    expect(compact.width, lessThan(regular.width));
    expect(compact.height, lessThan(regular.height));
  });
}
