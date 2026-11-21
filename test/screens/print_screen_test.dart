import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_photobooth/screens/print_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Small "sheet": left half red, right half blue. Synchronous, no engine work.
ui.Image sheetImage() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 18, 12),
      Paint()..color = const Color(0xFFFF0000),
    )
    ..drawRect(
      const Rect.fromLTWH(18, 0, 18, 12),
      Paint()..color = const Color(0xFF0000FF),
    );
  return recorder.endRecording().toImageSync(36, 12);
}

void main() {
  late List<int> printed;
  late int backs;
  late int startOvers;
  late List<bool> outcomes;
  Completer<void>? gate;
  Object? printError;
  bool failSheet = false;

  /// [share] false = no GIF/QR to share → the "Sent to print" popup.
  Future<void> pumpScreen(WidgetTester tester, {bool share = true}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    printed = [];
    backs = 0;
    startOvers = 0;
    outcomes = [];

    await tester.pumpWidget(
      MaterialApp(
        home: PrintScreen(
          buildSheet: () async {
            if (failSheet) throw Exception('decode failed');
            return sheetImage();
          },
          printSheet: (sheet, prints) async {
            printed.add(prints);
            if (gate != null) await gate!.future;
            if (printError != null) throw printError!;
          },
          onBack: () => backs++,
          onStartOver: () => startOvers++,
          onPrinted: share ? outcomes.add : null,
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    gate = null;
    printError = null;
    failSheet = false;
  });

  bool enabled(WidgetTester tester, String label) => tester
      .widget<TextButton>(
        find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
      )
      .enabled;

  testWidgets('shows title, preview and stepper starting at 2', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Your Photo is Ready!'), findsOneWidget);
    expect(find.text('Number of prints'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    expect(enabled(tester, 'Print Photo'), isTrue);
  });

  testWidgets('Print sends the chosen count, then reports success', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.bySemanticsLabel('Increase'));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.text('Print Photo'));
    await tester.pumpAndSettle();
    expect(printed, [4]);
    expect(outcomes, [true]);
    expect(find.text('Sent to print'), findsNothing, reason: 'no popup');
  });

  testWidgets('Print is disabled while a job is being sent', (tester) async {
    await pumpScreen(tester);
    gate = Completer<void>();
    await tester.tap(find.text('Print Photo'));
    await tester.pump();
    expect(find.text('Printing…'), findsOneWidget);
    expect(enabled(tester, 'Printing…'), isFalse);

    await tester.tap(find.text('Printing…'), warnIfMissed: false);
    expect(printed, [2], reason: 'double tap ignored');

    gate!.complete();
    await tester.pumpAndSettle();
    expect(outcomes, [true]);
  });

  testWidgets('printer error is reported, not thrown', (tester) async {
    await pumpScreen(tester);
    printError = Exception('No printer found');
    await tester.tap(find.text('Print Photo'));
    await tester.pumpAndSettle();
    expect(outcomes, [false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet failure → message, Print disabled', (tester) async {
    failSheet = true;
    await pumpScreen(tester);
    expect(find.textContaining("Couldn't make your photo"), findsOneWidget);
    expect(enabled(tester, 'Print Photo'), isFalse);
  });

  testWidgets('Back to Selection and Start Over', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Back to Selection'));
    await tester.tap(find.text('Start Over'));
    expect(backs, 1);
    expect(startOvers, 1);
  });

  group('nothing to share (no onPrinted) → popup, as in Python', () {
    testWidgets('success → "Sent to print", OK closes it', (tester) async {
      await pumpScreen(tester, share: false);
      await tester.tap(find.text('Print Photo'));
      await tester.pumpAndSettle();
      expect(printed, [2]);
      expect(find.text('Sent to print'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Sent to print'), findsNothing);
      expect(find.text('Print Photo'), findsOneWidget, reason: 'stays here');
    });

    testWidgets('every press prints again (Python behaviour)', (tester) async {
      await pumpScreen(tester, share: false);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Print Photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      expect(printed, [2, 2]);
    });

    testWidgets('printer error shows a message instead of crashing', (
      tester,
    ) async {
      await pumpScreen(tester, share: false);
      printError = Exception('No printer found');
      await tester.tap(find.text('Print Photo'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't print"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
