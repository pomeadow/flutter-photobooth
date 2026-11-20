import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_photobooth/services/printer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';

/// PNG of [w]×[h]: red top-left quadrant, everything else blue.
Future<Uint8List> markedPng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF0000FF),
    )
    ..drawRect(
      Rect.fromLTWH(0, 0, w / 2, h / 2),
      Paint()..color = const Color(0xFFFF0000),
    );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Color Function(int, int)> pixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (x, y) {
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(
      255,
      rgba.getUint8(i),
      rgba.getUint8(i + 1),
      rgba.getUint8(i + 2),
    );
  };
}

class FakeBackend implements PrintBackend {
  FakeBackend({
    this.canList = true,
    this.printers = const [],
    this.cancel = false,
  });

  final bool canList;
  final List<Printer> printers;
  final bool cancel;
  final List<({String printer, int pages, bool driver})> jobs = [];

  @override
  Future<bool> canListPrinters() async => canList;

  @override
  Future<List<Printer>> listPrinters() async => printers;

  @override
  Future<bool> printPdf(
    Printer printer,
    Uint8List pdf, {
    required String jobName,
    required bool useDriverSettings,
  }) async {
    final pages = RegExp(r'/Type\s*/Page\b')
        .allMatches(latin1.decode(pdf))
        .length;
    jobs.add((printer: printer.name, pages: pages, driver: useDriverSettings));
    return !cancel;
  }
}

Printer printer(String name, {bool available = true}) =>
    Printer(url: 'ipp://$name', name: name, isAvailable: available);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rules from python_parallel_print', () {
    test('copies = prints ÷ 2 (min 1)', () {
      expect(PrinterService.copiesFor(2), 1);
      expect(PrinterService.copiesFor(4), 2);
      expect(PrinterService.copiesFor(10), 5);
      expect(PrinterService.copiesFor(1), 1);
    });

    test('distribute spreads copies round-robin', () {
      expect(PrinterService.distribute(5, ['A', 'B', 'C']), {
        'A': 2,
        'B': 2,
        'C': 1,
      });
      expect(PrinterService.distribute(1, ['A', 'B'], startAt: 1), {'B': 1});
      expect(
        () => PrinterService.distribute(1, []),
        throwsA(isA<PrinterException>()),
      );
    });

    test('pngSize reads the header without decoding', () async {
      final size = PrinterService.pngSize(await markedPng(180, 120));
      expect([size.width, size.height], [180, 120]);
      expect(
        () => PrinterService.pngSize(Uint8List(30)),
        throwsA(isA<PrinterException>()),
      );
    });
  });

  group('rotateToPortrait', () {
    test('landscape turns 90° counter-clockwise (PIL rotate(90))', () async {
      final rotated = await PrinterService.rotateToPortrait(
        await markedPng(180, 120),
      );
      final size = PrinterService.pngSize(rotated);
      expect([size.width, size.height], [120, 180]);

      // CCW: the source's top-left (red) ends up bottom-left.
      final px = await pixels(rotated);
      expect(px(20, 160), const Color(0xFFFF0000), reason: 'bottom-left');
      expect(px(20, 20), const Color(0xFF0000FF), reason: 'top-left');
      expect(px(100, 160), const Color(0xFF0000FF), reason: 'bottom-right');
    });

    test('portrait is returned untouched', () async {
      final png = await markedPng(120, 180);
      expect(
        identical(await PrinterService.rotateToPortrait(png), png),
        isTrue,
      );
    });
  });

  test('PDF: one 4×6 in page per copy, no margins', () async {
    final pdf = await PrinterService.buildPdf(await markedPng(120, 180), 3);
    final text = latin1.decode(pdf);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 3);
    // 4×6 in = 288×432 pt.
    expect(text, matches(RegExp(r'/MediaBox\s*\[0 0 288 432\]')));
  });

  group('MockPrinterService', () {
    test('records jobs and alternates printers between guests', () async {
      final mock = MockPrinterService(printerNames: ['A', 'B']);
      final png = await markedPng(180, 120);
      await mock.printSheet(png, prints: 2);
      await mock.printSheet(png, prints: 2);
      expect(mock.jobs.map((j) => j.copiesPerPrinter), [
        {'A': 1},
        {'B': 1},
      ]);
    });
  });

  group('SystemPrinterService', () {
    late Uint8List sheet;
    setUpAll(() async => sheet = await markedPng(180, 120));

    test('uses only available printers matching the SELPHY filter', () async {
      final backend = FakeBackend(
        printers: [
          printer('Canon SELPHY CP1500 (2)'),
          printer('Office LaserJet'),
          printer('canon selphy cp1500'),
          printer('Canon SELPHY CP1500 (3)', available: false),
        ],
      );
      final service = SystemPrinterService(backend: backend);
      expect(await service.printers(), [
        'Canon SELPHY CP1500 (2)',
        'canon selphy cp1500',
      ]);
    });

    test('6 prints → 3 copies spread over 2 printers, in parallel', () async {
      final backend = FakeBackend(
        printers: [
          printer('Canon SELPHY CP1500 A'),
          printer('Canon SELPHY CP1500 B'),
        ],
      );
      final service = SystemPrinterService(backend: backend);
      final result = await service.printSheet(sheet, prints: 6);

      expect(result.copies, 3);
      expect(result.copiesPerPrinter, {
        'Canon SELPHY CP1500 A': 2,
        'Canon SELPHY CP1500 B': 1,
      });
      expect(backend.jobs.map((j) => '${j.printer}:${j.pages}').toSet(), {
        'Canon SELPHY CP1500 A:2',
        'Canon SELPHY CP1500 B:1',
      }, reason: 'one job per printer, one PDF page per copy');
    });

    test('next guest starts on the next printer', () async {
      final backend = FakeBackend(
        printers: [
          printer('Canon SELPHY CP1500 A'),
          printer('Canon SELPHY CP1500 B'),
        ],
      );
      final service = SystemPrinterService(backend: backend);
      await service.printSheet(sheet, prints: 2);
      await service.printSheet(sheet, prints: 2);
      expect(backend.jobs.map((j) => j.printer), [
        'Canon SELPHY CP1500 A',
        'Canon SELPHY CP1500 B',
      ]);
    });

    test('useDriverSettings is passed through (margin knob)', () async {
      final backend = FakeBackend(printers: [printer('Canon SELPHY CP1500')]);
      await SystemPrinterService(
        backend: backend,
        useDriverSettings: true,
      ).printSheet(sheet, prints: 2);
      expect(backend.jobs.single.driver, isTrue);
    });

    test('no matching printer → PrinterException', () async {
      final service = SystemPrinterService(
        backend: FakeBackend(printers: [printer('Office LaserJet')]),
      );
      await expectLater(
        service.printSheet(sheet, prints: 2),
        throwsA(isA<PrinterException>()),
      );
    });

    test('iPad (cannot list) needs usePrinters()', () async {
      final backend = FakeBackend(canList: false);
      final service = SystemPrinterService(backend: backend);
      await expectLater(service.printers(), throwsA(isA<PrinterException>()));

      service.usePrinters([printer('Picked AirPrint printer')]);
      await service.printSheet(sheet, prints: 2);
      expect(backend.jobs.single.printer, 'Picked AirPrint printer');
    });

    test('cancelled job → PrinterException', () async {
      final service = SystemPrinterService(
        backend: FakeBackend(
          printers: [printer('Canon SELPHY CP1500')],
          cancel: true,
        ),
      );
      await expectLater(
        service.printSheet(sheet, prints: 2),
        throwsA(isA<PrinterException>()),
      );
    });
  });
}
