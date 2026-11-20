import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_photobooth/app.dart';
import 'package:flutter_photobooth/config/templates.dart';
import 'package:flutter_photobooth/services/composite_service.dart';
import 'package:flutter_photobooth/services/printer_service.dart';
import 'package:flutter_photobooth/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_camera.dart';

/// Real services end to end (no UI): fake photos → session → composite →
/// saveAndPrint → file on disk + mock print job.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '2 photos, 6 prints: 1800×1200 @300 DPI saved, 3 copies printed',
    () async {
      final root = await Directory.systemTemp.createTemp('pipeline_');
      addTearDown(() => root.delete(recursive: true));
      final session = SessionService(root: root);
      final composer = CompositeService();
      final printer = MockPrinterService();
      final catalog = await TemplateCatalog.load();

      await session.createSession();
      final camera = FakeCameraService(warmUp: Duration.zero);
      await camera.start();
      for (var i = 0; i < 2; i++) {
        final shot = await camera.capture();
        await session.savePhoto(shot.bytes, extension: shot.extension);
      }
      camera.dispose();

      final photos = [for (final f in await session.listPhotos()) f.path];
      final sheet = await composer.compose(
        catalog.forSelectionCount(2).first,
        photos,
      );
      final file = await saveAndPrint(
        sheet: sheet,
        prints: 6,
        composer: composer,
        session: session,
        printer: printer,
      );
      sheet.dispose();

      expect(p.basename(file.path), startsWith('final_composite_'));
      final png = await file.readAsBytes();
      final size = PrinterService.pngSize(png);
      expect([size.width, size.height], [1800, 1200]);
      // pHYs = 11811 px/m (300 DPI).
      expect(ByteData.sublistView(png).getUint32(41), 11811);
      expect(printer.jobs.single.copies, 3);

      // Decodes fine (it's what gets printed).
      final codec = await ui.instantiateImageCodec(png);
      expect((await codec.getNextFrame()).image.width, 1800);
      composer.clearCache();
    },
  );
}
