import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_photobooth/app.dart';
import 'package:flutter_photobooth/services/gif_service.dart';
import 'package:flutter_photobooth/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class FailingGifs extends GifService {
  const FailingGifs();
  @override
  Future<Uint8List> create(
    List<String> photoPaths, {
    GifOptions options = const GifOptions(),
  }) => Future.error(Exception('encoder crashed'));
}

/// makeAndSaveGif with real files: the app shell's background GIF step.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SessionService sessions;

  Future<List<String>> fourPhotos() async {
    final paths = <String>[];
    for (final c in const [0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00]) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 320, 180),
        Paint()..color = Color(c),
      );
      final image = await recorder.endRecording().toImage(320, 180);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final photo = await sessions.savePhoto(
        png!.buffer.asUint8List(),
        extension: 'png',
      );
      paths.add(photo.path);
    }
    return paths;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('guest_gif_');
    sessions = SessionService(root: root);
  });
  tearDown(() => root.delete(recursive: true));

  List<String> gifsIn(Session s) => [
    for (final f in s.folder.listSync())
      if (f.path.endsWith('.gif')) p.basename(f.path),
  ];

  test('all 4 photos → GIF saved in the guest session', () async {
    final session = await sessions.createSession();
    final photos = await fourPhotos();

    final gif = await makeAndSaveGif(
      photos: photos,
      session: session,
      gifs: const GifService(),
      sessions: sessions,
    );
    expect(String.fromCharCodes(gif!.bytes.sublist(0, 6)), 'GIF89a');
    expect(gifsIn(session), hasLength(1));
    expect(gifsIn(session).single, startsWith('animation_'));
    expect(
      p.basename(gif.file!.path),
      gifsIn(session).single,
      reason: 'returns the saved file, so Drive gets the same name',
    );
  });

  test('save failure → bytes still returned, file null', () async {
    final session = await sessions.createSession();
    // Keep the photos outside the session folder, then remove the folder so
    // the GIF can be made but not saved.
    final kept = await Directory(p.join(root.path, 'kept')).create();
    final photos = [
      for (final path in await fourPhotos())
        (await File(path).copy(p.join(kept.path, p.basename(path)))).path,
    ];
    await session.folder.delete(recursive: true);

    final gif = await makeAndSaveGif(
      photos: photos,
      session: session,
      gifs: const GifService(),
      sessions: sessions,
    );
    expect(String.fromCharCodes(gif!.bytes.sublist(0, 6)), 'GIF89a');
    expect(gif.file, isNull);
  });

  test(
    'guest started over before it finished → still saved in THEIR folder',
    () async {
      final first = await sessions.createSession();
      final photos = await fourPhotos();

      final making = makeAndSaveGif(
        photos: photos,
        session: first,
        gifs: const GifService(),
        sessions: sessions,
      );
      sessions.reset(); // Start Over
      await Future<void>.delayed(const Duration(seconds: 1));
      final second = await sessions.createSession(); // next guest

      await making;
      expect(gifsIn(first), hasLength(1));
      expect(gifsIn(second), isEmpty, reason: "not the next guest's folder");
    },
  );

  test(
    'encoder failure → null (share screen hides the panel), no throw',
    () async {
      final session = await sessions.createSession();
      final gif = await makeAndSaveGif(
        photos: await fourPhotos(),
        session: session,
        gifs: const FailingGifs(),
        sessions: sessions,
      );
      expect(gif, isNull);
      expect(gifsIn(session), isEmpty);
    },
  );

  test('no photos or no session → null', () async {
    expect(
      await makeAndSaveGif(
        photos: const [],
        session: await sessions.createSession(),
        gifs: const GifService(),
        sessions: sessions,
      ),
      isNull,
    );
    expect(
      await makeAndSaveGif(
        photos: const ['x.jpg'],
        session: null,
        gifs: const GifService(),
        sessions: sessions,
      ),
      isNull,
    );
  });
}
