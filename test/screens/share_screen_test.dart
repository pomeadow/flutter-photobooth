import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_photobooth/screens/share_screen.dart';
import 'package:flutter_photobooth/services/drive_upload_service.dart';
import 'package:flutter_photobooth/services/gif_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 2-frame 8×4 GIF, encoded synchronously (pure Dart, no engine work).
Uint8List tinyGif() => GifService.encodeGif(
  frames: [
    Uint8List.fromList(List.filled(8 * 4 * 4, 255)),
    Uint8List.fromList(List.filled(8 * 4 * 4, 0)),
  ],
  order: const [0, 1],
  width: 8,
  height: 4,
  delayCentiseconds: 50,
  loopForever: true,
);

void main() {
  late int dones;

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool printed = true,
    Future<Uint8List?>? gif,
    Future<DriveFolder?>? driveFolder,
    Duration idleTimeout = const Duration(seconds: 60),
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dones = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ShareScreen(
          printed: printed,
          gif: gif,
          driveFolder: driveFolder,
          idleTimeout: idleTimeout,
          onDone: () => dones++,
        ),
      ),
    );
    await tester.pump();
  }

  final folder = DriveFolder(
    id: 'abc',
    url: Uri.parse('https://drive.google.com/drive/folders/abc'),
  );

  testWidgets('printed → "Sent to print!"', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Sent to print!'), findsOneWidget);
    expect(find.textContaining("Couldn't print"), findsNothing);
  });

  testWidgets('print failed → note, GIF and QR still shown', (tester) async {
    await pumpScreen(
      tester,
      printed: false,
      gif: Future.value(tinyGif()),
      driveFolder: Future.value(folder),
    );
    await tester.pump();
    expect(find.textContaining("Couldn't print"), findsOneWidget);
    expect(find.byKey(const ValueKey('guest-gif')), findsOneWidget);
    expect(find.byKey(const ValueKey('drive-qr')), findsOneWidget);
  });

  testWidgets('Done → onDone once', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Done'));
    await tester.tap(find.text('Done'));
    expect(dones, 1);
  });

  group('idle timeout', () {
    testWidgets('no taps → onDone after the timeout', (tester) async {
      await pumpScreen(tester, idleTimeout: const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 9));
      expect(dones, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(dones, 1);
    });

    testWidgets('a tap restarts the countdown', (tester) async {
      await pumpScreen(tester, idleTimeout: const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 8));
      await tester.tapAt(const Offset(100, 500));
      await tester.pump(const Duration(seconds: 8));
      expect(dones, 0, reason: '16 s total, but only 8 s since the tap');
      await tester.pump(const Duration(seconds: 3));
      expect(dones, 1);
    });

    testWidgets('Done then timeout → still once', (tester) async {
      await pumpScreen(tester, idleTimeout: const Duration(seconds: 10));
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(seconds: 11));
      expect(dones, 1);
    });
  });

  group('GIF panel', () {
    testWidgets('no gif future → no panel (feature off)', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Your GIF'), findsNothing);
    });

    testWidgets('spinner while being made, then the GIF plays', (tester) async {
      final making = Completer<Uint8List?>();
      await pumpScreen(tester, gif: making.future);
      expect(find.text('Your GIF'), findsOneWidget);
      expect(find.byKey(const ValueKey('guest-gif')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      making.complete(tinyGif());
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('guest-gif')), findsOneWidget);
    });

    testWidgets('GIF could not be made → panel hidden', (tester) async {
      await pumpScreen(tester, gif: Future.value(null));
      await tester.pump();
      expect(find.text('Your GIF'), findsNothing);
    });
  });

  group('QR panel', () {
    testWidgets('no folder future → no panel (feature off)', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Scan for your photos'), findsNothing);
      expect(find.byKey(const ValueKey('drive-qr')), findsNothing);
    });

    testWidgets('spinner while waiting, then the QR code', (tester) async {
      final making = Completer<DriveFolder?>();
      await pumpScreen(tester, driveFolder: making.future);
      expect(find.text('Scan for your photos'), findsOneWidget);
      expect(find.byKey(const ValueKey('drive-qr')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      making.complete(folder);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('drive-qr')), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('folder failed → panel hidden', (tester) async {
      await pumpScreen(tester, driveFolder: Future.value(null));
      await tester.pump();
      expect(find.text('Scan for your photos'), findsNothing);
    });

    testWidgets('GIF and QR side by side fit the canvas', (tester) async {
      await pumpScreen(
        tester,
        gif: Future.value(tinyGif()),
        driveFolder: Future.value(folder),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('guest-gif')), findsOneWidget);
      expect(find.byKey(const ValueKey('drive-qr')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });
  });
}
