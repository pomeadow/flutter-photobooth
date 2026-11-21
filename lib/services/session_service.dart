import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/templates.dart';

/// One guest's visit: a folder of photos plus the frame they picked.
class Session {
  Session._(this.folder, this.startedAt);

  final Directory folder;
  final DateTime startedAt;

  /// Frame chosen on the selection screen (Python's `template_path`).
  FrameTemplate? template;
}

/// Creates per-guest session folders and reads/writes the files in them.
///
/// Port of py-photobooth `controllers/session_manager.py`. Layout:
/// ```
/// <root>/session_YYYYmmdd_HHMMSS/
///   YYYY-mm-dd HHMMSS.ffffff_image.jpg        ← captured photos
///   preview_strip_<n>photos.png               ← selection-screen preview
///   final_composite_YYYYmmdd_HHMMSS.png       ← each Print press
///   animation_YYYYmmdd_HHMMSS.gif             ← GIF (GifService)
/// ```
class SessionService {
  SessionService({required this.root, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// Sessions under `<app documents>/photobooth_sessions` — works on
  /// macOS, Windows and iPad (Python used the working directory, which iPad
  /// doesn't have).
  static Future<SessionService> inDocuments() async {
    final docs = await getApplicationDocumentsDirectory();
    return SessionService(
      root: Directory(p.join(docs.path, 'photobooth_sessions')),
    );
  }

  final Directory root;
  final DateTime Function() _now;

  Session? _current;

  /// The active session, or null between guests.
  Session? get current => _current;

  /// Image extensions treated as photos when listing.
  static const photoExtensions = {'.jpg', '.jpeg', '.png'};

  /// Starts a new session folder `session_YYYYmmdd_HHMMSS`.
  ///
  /// If that name is taken (two sessions in the same second), appends `_2`,
  /// `_3`, … — Python reused the folder and mixed two guests' photos.
  Future<Session> createSession() async {
    final now = _now();
    final base = 'session_${_compact(now)}';
    var folder = Directory(p.join(root.path, base));
    for (var n = 2; await folder.exists(); n++) {
      folder = Directory(p.join(root.path, '${base}_$n'));
    }
    await folder.create(recursive: true);
    return _current = Session._(folder, now);
  }

  /// Saves captured photo [bytes] as `YYYY-mm-dd HHMMSS.ffffff_image.<ext>`
  /// (Python's name). [extension] should match the bytes — camera plugins
  /// give JPEG, so photos are stored as-is rather than re-encoded.
  Future<File> savePhoto(Uint8List bytes, {String extension = 'jpg'}) async {
    final session = _require();
    final name = '${_withMicros(_now())}_image.$extension';
    return _writeUnique(session, name, bytes);
  }

  /// Captured photos in the current session, oldest first. Excludes preview
  /// strips and composites (same filter as Python).
  Future<List<File>> listPhotos() async {
    final session = _current;
    if (session == null || !await session.folder.exists()) return [];
    final photos = <File>[];
    await for (final entity in session.folder.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!photoExtensions.contains(p.extension(name).toLowerCase())) continue;
      if (name.contains('preview_strip') || name.contains('composite')) {
        continue;
      }
      photos.add(entity);
    }
    photos.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return photos;
  }

  /// Writes the selection-screen preview as `preview_strip_<n>photos.png`.
  Future<File> savePreviewStrip(Uint8List png, int photoCount) =>
      _write(_require(), 'preview_strip_${photoCount}photos.png', png);

  /// Deletes all preview strips (Python did this on entering selection).
  Future<void> deletePreviewStrips() async {
    final session = _current;
    if (session == null || !await session.folder.exists()) return;
    await for (final entity in session.folder.list()) {
      if (entity is File && p.basename(entity.path).contains('preview_strip')) {
        await entity.delete();
      }
    }
  }

  /// Writes a print-ready composite as `final_composite_YYYYmmdd_HHMMSS.png`.
  /// Every Print press makes a new file (never overwrites — suffixed if two
  /// presses land in the same second).
  Future<File> saveFinalComposite(Uint8List png) =>
      _writeUnique(_require(), 'final_composite_${_compact(_now())}.png', png);

  /// Writes an animated GIF (see GifService) as
  /// `animation_YYYYmmdd_HHMMSS.gif`; never overwrites.
  ///
  /// Pass the [session] the photos came from: the GIF is made in the
  /// background, and the guest may have pressed Start Over (or the next guest
  /// started) by the time it's done. Defaults to the current session.
  Future<File> saveGif(Uint8List gif, {Session? session}) => _writeUnique(
    session ?? _require(),
    'animation_${_compact(_now())}.gif',
    gif,
  );

  /// Ends the session (back to title). Files stay on disk.
  void reset() => _current = null;

  // ---------------------------------------------------------------------------

  Session _require() {
    final session = _current;
    if (session == null) {
      // Python silently wrote to the working directory here.
      throw StateError('No active session — call createSession() first.');
    }
    return session;
  }

  Future<File> _write(Session session, String name, Uint8List bytes) =>
      File(p.join(session.folder.path, name)).writeAsBytes(bytes, flush: true);

  Future<File> _writeUnique(Session s, String name, Uint8List bytes) async {
    final stem = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var candidate = name;
    for (
      var n = 2;
      await File(p.join(s.folder.path, candidate)).exists();
      n++
    ) {
      candidate = '${stem}_$n$ext';
    }
    return _write(s, candidate, bytes);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `YYYYmmdd_HHMMSS`
  static String _compact(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}_'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  /// `YYYY-mm-dd HHMMSS.ffffff` (Python `%Y-%m-%d %H%M%S.%f`).
  static String _withMicros(DateTime t) {
    final micros = (t.millisecond * 1000 + t.microsecond).toString().padLeft(
      6,
      '0',
    );
    return '${t.year}-${_two(t.month)}-${_two(t.day)} '
        '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}.$micros';
  }
}
