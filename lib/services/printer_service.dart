import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrinterException implements Exception {
  PrinterException(this.message);
  final String message;

  @override
  String toString() => 'PrinterException: $message';
}

/// What happened to one Print press.
class PrintResult {
  const PrintResult({required this.copies, required this.copiesPerPrinter});

  /// Sheets printed in total (`prints ÷ 2`).
  final int copies;

  /// Printer name → sheets sent to it.
  final Map<String, int> copiesPerPrinter;

  @override
  String toString() => 'PrintResult($copies copies: $copiesPerPrinter)';
}

/// Sends a composite sheet to the photo printer(s).
///
/// Port of py-photobooth's `python_parallel_print` (`Printer` /
/// `MockPrinter`). Same rules:
/// - [copiesFor]: the guest picks a number of *strips*; each 4×6 sheet holds
///   2 (cut in half), so `copies = prints ÷ 2`.
/// - Landscape sheets are rotated to portrait ([rotateToPortrait]).
/// - With several matching printers, copies are spread across them
///   ([distribute]) and printed in parallel.
abstract class PrinterService {
  /// Names of the printers that would be used now.
  Future<List<String>> printers();

  /// Prints [sheetPng] (a 300-DPI composite) for [prints] guest strips.
  Future<PrintResult> printSheet(
    Uint8List sheetPng, {
    required int prints,
    String jobName = 'Photobooth',
  });

  /// Python: `int(prints / 2)`, at least 1.
  static int copiesFor(int prints) => math.max(1, prints ~/ 2);

  /// Spreads [copies] over [printers] round-robin, starting at [startAt]
  /// (so consecutive guests don't always load printer 0 first).
  /// Returns name → copies, only for printers that get at least one.
  static Map<String, int> distribute(
    int copies,
    List<String> printers, {
    int startAt = 0,
  }) {
    if (printers.isEmpty) throw PrinterException('No printers');
    final counts = <String, int>{};
    for (var i = 0; i < copies; i++) {
      final name = printers[(startAt + i) % printers.length];
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }

  /// Width and height from a PNG header, without decoding.
  static ({int width, int height}) pngSize(Uint8List png) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (png.length < 24 ||
        !List.generate(8, (i) => png[i] == signature[i]).every((ok) => ok)) {
      throw PrinterException('Not a PNG');
    }
    final view = ByteData.sublistView(png);
    return (width: view.getUint32(16), height: view.getUint32(20));
  }

  /// Python `autorotate`: landscape → portrait by rotating 90°
  /// counter-clockwise (PIL `rotate(90, expand=True)`). Portrait sheets are
  /// returned unchanged.
  static Future<Uint8List> rotateToPortrait(Uint8List png) async {
    final size = pngSize(png);
    if (size.width <= size.height) return png;

    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final recorder = ui.PictureRecorder();
      // Counter-clockwise: the source's top edge becomes the left edge.
      Canvas(recorder)
        ..translate(0, image.width.toDouble())
        ..rotate(-math.pi / 2)
        ..drawImage(image, Offset.zero, Paint());
      final picture = recorder.endRecording();
      final rotated = await picture.toImage(image.height, image.width);
      picture.dispose();
      try {
        final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      } finally {
        rotated.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  /// 4×6 in portrait page, no margins.
  static final PdfPageFormat sheetFormat = PdfPageFormat(
    4 * PdfPageFormat.inch,
    6 * PdfPageFormat.inch,
    marginAll: 0,
  );

  /// PDF with [pages] identical pages, each [portraitPng] filling a 4×6 in
  /// page edge to edge. One page per copy keeps copies working on every
  /// platform (the print APIs have no portable copy count).
  static Future<Uint8List> buildPdf(Uint8List portraitPng, int pages) {
    final doc = pw.Document(title: 'Photobooth print');
    final image = pw.MemoryImage(portraitPng);
    for (var i = 0; i < pages; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: sheetFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) =>
              pw.SizedBox.expand(child: pw.Image(image, fit: pw.BoxFit.fill)),
        ),
      );
    }
    return doc.save();
  }
}

/// Logs instead of printing — Python's `MockPrinter`. The app's default until
/// the real SELPHY setup is verified. [jobs] records every call.
class MockPrinterService implements PrinterService {
  MockPrinterService({this.printerNames = const ['Mock SELPHY CP1500']});

  final List<String> printerNames;
  final List<PrintResult> jobs = [];
  int _next = 0;

  @override
  Future<List<String>> printers() async => printerNames;

  @override
  Future<PrintResult> printSheet(
    Uint8List sheetPng, {
    required int prints,
    String jobName = 'Photobooth',
  }) async {
    final size = PrinterService.pngSize(sheetPng);
    final copies = PrinterService.copiesFor(prints);
    final spread = PrinterService.distribute(
      copies,
      printerNames,
      startAt: _next,
    );
    _next = (_next + copies) % printerNames.length;
    final result = PrintResult(copies: copies, copiesPerPrinter: spread);
    jobs.add(result);
    debugPrint(
      'MOCK PRINT "$jobName": ${size.width}×${size.height}'
      '${size.width > size.height ? ' (rotated to portrait)' : ''}, '
      '$prints prints → $result',
    );
    return result;
  }
}

/// The platform calls [SystemPrinterService] needs — a seam so tests don't
/// touch real printers.
abstract class PrintBackend {
  /// False on iOS: printers must be picked by the user instead.
  Future<bool> canListPrinters();
  Future<List<Printer>> listPrinters();
  Future<bool> printPdf(
    Printer printer,
    Uint8List pdf, {
    required String jobName,
    required bool useDriverSettings,
  });
}

class PrintingPackageBackend implements PrintBackend {
  const PrintingPackageBackend();

  @override
  Future<bool> canListPrinters() async =>
      (await Printing.info()).canListPrinters;

  @override
  Future<List<Printer>> listPrinters() => Printing.listPrinters();

  @override
  Future<bool> printPdf(
    Printer printer,
    Uint8List pdf, {
    required String jobName,
    required bool useDriverSettings,
  }) async => Printing.directPrintPdf(
    printer: printer,
    onLayout: (_) async => pdf,
    name: jobName,
    format: PrinterService.sheetFormat,
    // The PDF is already laid out at exactly 4×6 in.
    dynamicLayout: false,
    usePrinterSettings: useDriverSettings,
  );
}

/// Real printing through the `printing` package: Windows print spooler,
/// AirPrint on macOS/iPad. No dialogs (kiosk).
///
/// - macOS/Windows: uses every available printer whose name contains
///   [nameFilter] (Python's default "Canon SELPHY CP1500").
/// - iPad: printers can't be listed; call [usePrinters] with the printer the
///   operator picked (`Printing.pickPrinter`) before printing.
class SystemPrinterService implements PrinterService {
  SystemPrinterService({
    this.nameFilter = 'Canon SELPHY CP1500',
    this.useDriverSettings = false,
    this.backend = const PrintingPackageBackend(),
  });

  /// Printers whose name contains this (case-insensitive) are used.
  final String nameFilter;

  /// Windows only: use the printer driver's paper/margin setup instead of
  /// our 4×6 in page. A knob for the "print slightly outside the boundaries"
  /// issue — which setting is right depends on the real SELPHY driver.
  final bool useDriverSettings;

  /// Platform printing calls; tests inject a fake.
  final PrintBackend backend;
  List<Printer>? _picked;
  int _next = 0;

  /// For iPad (or to override discovery): print to exactly these printers.
  void usePrinters(List<Printer> printers) => _picked = List.of(printers);

  Future<List<Printer>> _targets() async {
    final picked = _picked;
    if (picked != null && picked.isNotEmpty) return picked;
    if (!await backend.canListPrinters()) {
      throw PrinterException(
        'This device cannot list printers — pick one with usePrinters().',
      );
    }
    final filter = nameFilter.toLowerCase();
    final found = [
      for (final p in await backend.listPrinters())
        if (p.isAvailable && p.name.toLowerCase().contains(filter)) p,
    ]..sort((a, b) => a.name.compareTo(b.name));
    if (found.isEmpty) {
      throw PrinterException('No printer found matching "$nameFilter".');
    }
    return found;
  }

  @override
  Future<List<String>> printers() async => [
    for (final p in await _targets()) p.name,
  ];

  @override
  Future<PrintResult> printSheet(
    Uint8List sheetPng, {
    required int prints,
    String jobName = 'Photobooth',
  }) async {
    final targets = await _targets();
    final copies = PrinterService.copiesFor(prints);
    final spread = PrinterService.distribute(copies, [
      for (final p in targets) p.name,
    ], startAt: _next);
    _next = (_next + copies) % targets.length;

    final portrait = await PrinterService.rotateToPortrait(sheetPng);
    // One job per printer, all in parallel (Python's parallel printing).
    final results = await Future.wait([
      for (final MapEntry(key: name, value: count) in spread.entries)
        PrinterService.buildPdf(portrait, count).then(
          (pdf) => backend.printPdf(
            targets.firstWhere((p) => p.name == name),
            pdf,
            jobName: jobName,
            useDriverSettings: useDriverSettings,
          ),
        ),
    ]);
    if (results.contains(false)) {
      throw PrinterException('A print job was cancelled.');
    }
    return PrintResult(copies: copies, copiesPerPrinter: spread);
  }
}
