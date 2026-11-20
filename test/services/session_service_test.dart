import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_photobooth/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late DateTime now;
  late SessionService service;

  final bytes = Uint8List.fromList([1, 2, 3]);
  String name(File f) => p.basename(f.path);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('photobooth_test_');
    now = DateTime(2026, 11, 19, 14, 5, 9, 123, 456);
    service = SessionService(root: root, clock: () => now);
  });

  tearDown(() => root.delete(recursive: true));

  test('creates session_YYYYmmdd_HHMMSS under root', () async {
    final session = await service.createSession();
    expect(p.basename(session.folder.path), 'session_20261119_140509');
    expect(await session.folder.exists(), isTrue);
    expect(service.current, same(session));
  });

  test('two sessions in the same second get separate folders', () async {
    final a = await service.createSession();
    final b = await service.createSession();
    final c = await service.createSession();
    expect(p.basename(a.folder.path), 'session_20261119_140509');
    expect(p.basename(b.folder.path), 'session_20261119_140509_2');
    expect(p.basename(c.folder.path), 'session_20261119_140509_3');
  });

  test('saves photos with the Python filename format', () async {
    await service.createSession();
    final file = await service.savePhoto(bytes);
    expect(name(file), '2026-11-19 140509.123456_image.jpg');
    expect(await file.readAsBytes(), bytes);

    final png = await service.savePhoto(bytes, extension: 'png');
    expect(name(png), '2026-11-19 140509.123456_image.png');

    // Same instant, same extension → suffixed, never overwritten.
    final again = await service.savePhoto(bytes);
    expect(name(again), '2026-11-19 140509.123456_image_2.jpg');
  });

  test('lists only photos, oldest first', () async {
    await service.createSession();
    now = DateTime(2026, 11, 19, 14, 5, 20);
    await service.savePhoto(bytes);
    now = DateTime(2026, 11, 19, 14, 5, 10);
    await service.savePhoto(bytes, extension: 'png');
    await service.savePreviewStrip(bytes, 2);
    await service.saveFinalComposite(bytes);

    final photos = (await service.listPhotos()).map(name).toList();
    expect(photos, [
      '2026-11-19 140510.000000_image.png',
      '2026-11-19 140520.000000_image.jpg',
    ]);
  });

  test('preview strips are named by count and can be deleted', () async {
    final session = await service.createSession();
    final strip = await service.savePreviewStrip(bytes, 4);
    expect(name(strip), 'preview_strip_4photos.png');

    await service.deletePreviewStrips();
    expect(await strip.exists(), isFalse);
    expect(await session.folder.exists(), isTrue);
  });

  test('every Print press makes a new composite file', () async {
    await service.createSession();
    final a = await service.saveFinalComposite(bytes);
    final b = await service.saveFinalComposite(bytes);
    expect(name(a), 'final_composite_20261119_140509.png');
    expect(name(b), 'final_composite_20261119_140509_2.png');
  });

  test('reset ends the session but keeps the files', () async {
    final session = await service.createSession();
    final photo = await service.savePhoto(bytes);
    service.reset();

    expect(service.current, isNull);
    expect(await service.listPhotos(), isEmpty);
    expect(await photo.exists(), isTrue);
    expect(await session.folder.exists(), isTrue);
  });

  test('writing without a session throws (Python wrote to cwd)', () {
    expect(() => service.savePhoto(bytes), throwsStateError);
    expect(() => service.saveFinalComposite(bytes), throwsStateError);
  });
}
