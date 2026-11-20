import 'package:material_ui/material_ui.dart';
import 'package:flutter_photobooth/widgets/step_selector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hosts a StepSelector with its value in local state, like a real screen.
class _Host extends StatefulWidget {
  const _Host({this.initial = 2, this.min = 2, this.max});

  final int initial;
  final int min;
  final int? max;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int value = widget.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: StepSelector(
          value: value,
          min: widget.min,
          max: widget.max,
          label: 'Number of prints',
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    ),
  );
}

Future<void> _tapPlus(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Increase'));
  await t.pump();
}

Future<void> _tapMinus(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Decrease'), warnIfMissed: false);
  await t.pump();
}

void main() {
  testWidgets('print-screen config: starts 2, steps by 2, no max', (t) async {
    await t.pumpWidget(const _Host());
    expect(find.text('Number of prints'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await _tapPlus(t);
    }
    expect(find.text('12'), findsOneWidget);

    await _tapMinus(t);
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('cannot go below min', (t) async {
    await t.pumpWidget(const _Host());
    await _tapMinus(t);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('clamps to max instead of overshooting (Python bug)', (t) async {
    await t.pumpWidget(const _Host(initial: 4, max: 5));
    await _tapPlus(t);
    expect(find.text('5'), findsOneWidget);

    // At max, + is disabled.
    await t.tap(find.bySemanticsLabel('Increase'), warnIfMissed: false);
    await t.pump();
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('clamps to min instead of undershooting', (t) async {
    await t.pumpWidget(const _Host(initial: 3, min: 2));
    await _tapMinus(t);
    expect(find.text('2'), findsOneWidget);
  });
}
