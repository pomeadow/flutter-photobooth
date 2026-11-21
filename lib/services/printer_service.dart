import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

class PrinterException implements Exception {
  PrinterException(this.message);
  final String message;

  @override
  String toString() => 'PrinterException: $message';
}

/// What happened to one Print press.
class PrintResult {
  const PrintResult({required this.copies, this.serverReply});

  /// Sheets requested (`prints ÷ 2`).
  final int copies;

  /// The print server's reply, if any.
  final String? serverReply;

  @override
  String toString() => 'PrintResult($copies copies)';
}

/// Hands a finished sheet to whatever prints it.
///
/// **Printing itself is not part of this app.** The user's separate printer
/// code (python_parallel_print) owns the Canon SELPHY CP1500 queue: it
/// rotates landscape sheets to portrait and shares copies round-robin across
/// all connected printers. This app only sends it the sheet and a copy count.
abstract class PrinterService {
  /// Sends [sheetPng] (a 300-DPI composite, as composed — not rotated) for
  /// [prints] guest strips. Throws [PrinterException] on failure.
  Future<PrintResult> printSheet(
    Uint8List sheetPng, {
    required int prints,
    String jobName = 'Photobooth',
  });

  /// Each 4×6 sheet holds 2 strips (cut in half): Python's `int(prints/2)`,
  /// at least 1.
  static int copiesFor(int prints) => math.max(1, prints ~/ 2);

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
}

/// Logs instead of printing — Python's `MockPrinter`. The default until a
/// print server is configured. [jobs] records every call.
class MockPrinterService implements PrinterService {
  final List<PrintResult> jobs = [];

  @override
  Future<PrintResult> printSheet(
    Uint8List sheetPng, {
    required int prints,
    String jobName = 'Photobooth',
  }) async {
    final size = PrinterService.pngSize(sheetPng);
    final result = PrintResult(copies: PrinterService.copiesFor(prints));
    jobs.add(result);
    debugPrint(
      'MOCK PRINT "$jobName": ${size.width}×${size.height}, '
      '$prints prints → ${result.copies} sheet(s)',
    );
    return result;
  }
}

/// Sends the sheet to the user's separate print server over HTTP, so any
/// booth device (Mac, Windows, iPad) can print through one print PC — or the
/// same machine via `localhost`.
///
/// Contract (see README → "Print server"):
/// ```
/// POST {server}/print?copies=<sheets>&name=<job name>
/// Content-Type: image/png
/// <PNG bytes: the 300-DPI sheet, as composed>
/// → 2xx = accepted (body: optional message); anything else = error
/// ```
class NetworkPrinterService implements PrinterService {
  NetworkPrinterService({
    required this.server,
    this.connectTimeout = const Duration(seconds: 5),
    this.timeout = const Duration(seconds: 30),
  });

  /// e.g. `http://192.168.1.50:8765` or `http://localhost:8765`.
  final Uri server;
  final Duration connectTimeout;

  /// Whole request, including upload (sheets are ~1–4 MB).
  final Duration timeout;

  Uri printUri({required int copies, required String jobName}) =>
      server.replace(
        path: '${server.path.replaceAll(RegExp(r'/+$'), '')}/print',
        queryParameters: {'copies': '$copies', 'name': jobName},
      );

  @override
  Future<PrintResult> printSheet(
    Uint8List sheetPng, {
    required int prints,
    String jobName = 'Photobooth',
  }) async {
    PrinterService.pngSize(sheetPng); // reject non-PNG early
    final copies = PrinterService.copiesFor(prints);
    final uri = printUri(copies: copies, jobName: jobName);

    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final reply = await () async {
        final request = await client.postUrl(uri);
        request.headers.contentType = ContentType('image', 'png');
        request.contentLength = sheetPng.length;
        request.add(sheetPng);
        final response = await request.close();
        final body = await utf8.decodeStream(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw PrinterException(
            'Print server said ${response.statusCode}'
            '${body.isEmpty ? '' : ': ${body.trim()}'}',
          );
        }
        return body.trim();
      }().timeout(timeout);
      return PrintResult(
        copies: copies,
        serverReply: reply.isEmpty ? null : reply,
      );
    } on PrinterException {
      rethrow;
    } on TimeoutException {
      throw PrinterException('Print server at $server did not answer in time');
    } on SocketException catch (error) {
      throw PrinterException(
        'Print server not reachable at $server (${error.message})',
      );
    } on HttpException catch (error) {
      throw PrinterException('Print server error: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }
}
