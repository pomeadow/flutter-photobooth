import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_photobooth/services/printer_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal valid PNG header: signature + IHDR with [w]×[h], plus filler.
Uint8List fakePng(int w, int h) {
  final bytes = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add([0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  final size = ByteData(8)
    ..setUint32(0, w)
    ..setUint32(4, h);
  bytes
    ..add(size.buffer.asUint8List())
    ..add(List.filled(100, 7));
  return bytes.takeBytes();
}

/// One request as the print server saw it.
typedef Received = ({
  String method,
  String path,
  Map<String, String> query,
  String? contentType,
  Uint8List body,
});

void main() {
  group('rules', () {
    test('copies = prints ÷ 2 (min 1), as in py-photobooth', () {
      expect(PrinterService.copiesFor(2), 1);
      expect(PrinterService.copiesFor(6), 3);
      expect(PrinterService.copiesFor(1), 1);
    });

    test('pngSize reads the header without decoding', () {
      final size = PrinterService.pngSize(fakePng(1800, 1200));
      expect([size.width, size.height], [1800, 1200]);
      expect(
        () => PrinterService.pngSize(Uint8List(30)),
        throwsA(isA<PrinterException>()),
      );
    });
  });

  test('MockPrinterService records copies', () async {
    final mock = MockPrinterService();
    await mock.printSheet(fakePng(1800, 1200), prints: 4);
    expect(mock.jobs.single.copies, 2);
  });

  group('NetworkPrinterService (real local HTTP server)', () {
    late HttpServer server;
    late List<Received> received;
    late Future<void> Function(HttpRequest) respond;

    setUp(() async {
      received = [];
      respond = (req) async {
        req.response.write('queued');
        await req.response.close();
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = BytesBuilder();
        await for (final chunk in req) {
          body.add(chunk);
        }
        received.add((
          method: req.method,
          path: req.uri.path,
          query: req.uri.queryParameters,
          contentType: req.headers.contentType?.mimeType,
          body: body.takeBytes(),
        ));
        await respond(req);
      });
    });
    tearDown(() => server.close(force: true));

    Uri base([String path = '']) =>
        Uri.parse('http://127.0.0.1:${server.port}$path');

    test('POST /print?copies&name with the PNG as-is', () async {
      final png = fakePng(1800, 1200);
      final result = await NetworkPrinterService(
        server: base(),
      ).printSheet(png, prints: 6, jobName: 'final_composite_20261121_101500');

      final req = received.single;
      expect(req.method, 'POST');
      expect(req.path, '/print');
      expect(req.query, {
        'copies': '3',
        'name': 'final_composite_20261121_101500',
      });
      expect(req.contentType, 'image/png');
      expect(req.body, png, reason: 'sent untouched (no rotation)');
      expect(result.copies, 3);
      expect(result.serverReply, 'queued');
    });

    test(
      'server URL with a path / trailing slash still hits …/print',
      () async {
        await NetworkPrinterService(server: base('/booth/'))
            .printSheet(fakePng(10, 10), prints: 2);
        expect(received.single.path, '/booth/print');
      },
    );

    test('server error → PrinterException with its message', () async {
      respond = (req) async {
        req.response
          ..statusCode = 503
          ..write('No SELPHY printers found');
        await req.response.close();
      };
      await expectLater(
        NetworkPrinterService(server: base())
            .printSheet(fakePng(10, 10), prints: 2),
        throwsA(
          isA<PrinterException>().having(
            (e) => e.message,
            'message',
            allOf(contains('503'), contains('No SELPHY printers found')),
          ),
        ),
      );
    });

    test('server not running → "not reachable"', () async {
      final port = server.port;
      await server.close(force: true);
      await expectLater(
        NetworkPrinterService(server: Uri.parse('http://127.0.0.1:$port'))
            .printSheet(fakePng(10, 10), prints: 2),
        throwsA(
          isA<PrinterException>().having(
            (e) => e.message,
            'message',
            contains('not reachable'),
          ),
        ),
      );
    });

    test('server never answers → timeout PrinterException', () async {
      respond = (_) => Completer<void>().future; // hang
      await expectLater(
        NetworkPrinterService(
          server: base(),
          timeout: const Duration(milliseconds: 300),
        ).printSheet(fakePng(10, 10), prints: 2),
        throwsA(
          isA<PrinterException>().having(
            (e) => e.message,
            'message',
            contains('did not answer'),
          ),
        ),
      );
    });

    test('non-PNG is rejected before any network call', () async {
      await expectLater(
        NetworkPrinterService(server: base())
            .printSheet(Uint8List(50), prints: 2),
        throwsA(isA<PrinterException>()),
      );
      expect(received, isEmpty);
    });
  });
}
