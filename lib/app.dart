import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_photobooth/services/drive_upload_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'config/templates.dart';
import 'screens/camera_screen.dart';
import 'screens/print_screen.dart';
import 'screens/selection_screen.dart';
import 'screens/share_screen.dart';
import 'screens/title_screen.dart';
import 'services/camera/camera_service.dart';
import 'services/camera/macos_camera_service.dart';
import 'services/camera/plugin_camera_service.dart';
import 'services/composite_service.dart';
import 'services/gif_service.dart';
import 'services/printer_service.dart';
import 'services/session_service.dart';
import 'services/sound_service.dart';
import 'theme/app_theme.dart';

/// The real camera for this platform (Python's `.env` camera settings are
/// [CameraConfig] defaults for now). There is no fake camera in the app —
/// like py-photobooth; the fake lives in `test/support/` for tests only.
CameraService createCamera() {
  if (Platform.isMacOS) return MacosCameraService();
  if (Platform.isIOS) {
    // iPad booth: the front camera faces the guests.
    return PluginCameraService(
      config: const CameraConfig(facing: CameraFacing.front),
    );
  }
  // Windows (+ Android/web via the `camera` plugin). Unsupported platforms
  // report "No camera found" through the camera status.
  return PluginCameraService();
}

/// The Print button's work: encode [sheet] at 300 DPI, save a new
/// `final_composite_*.png` in the session (every press, as in Python), then
/// send it to [printer]. Returns the saved file.
Future<File> saveAndPrint({
  required ui.Image sheet,
  required int prints,
  required CompositeService composer,
  required SessionService session,
  required PrinterService printer,
}) async {
  final png = await composer.encodePng(sheet);
  final file = await session.saveFinalComposite(png);
  final name = file.uri.pathSegments.last.replaceAll('.png', '');
  await printer.printSheet(png, prints: prints, jobName: name);
  return file;
}

/// The guest's GIF (made after the camera screen, shown on the share
/// screen). On unless `--dart-define=GIF=off`. With GIF and Drive both off,
/// Print shows Python's "Sent to print" popup instead of the share screen.
const String gifChoice = String.fromEnvironment('GIF', defaultValue: 'on');

/// Null = feature off: no GIF is made, saved, shown or uploaded.
GifService? createGifService() =>
    gifChoice == 'off' ? null : const GifService();

/// Upload to Drive + QR code on the share screen. Off unless set:
/// `--dart-define=DRIVE_SERVER=http://host:8766`
/// `--dart-define=DRIVE_API_KEY=...` (if the server sets API_KEY)
const String driveServer = String.fromEnvironment('DRIVE_SERVER');
const String driveApiKey = String.fromEnvironment('DRIVE_API_KEY');

/// Null = feature off: nothing is uploaded and no QR is shown.
DriveUploadService? createDriveUploader() => driveServer.isEmpty
    ? null
    : NetworkDriveUploadService(
        server: Uri.parse(driveServer),
        apiKey: driveApiKey.isEmpty ? null : driveApiKey,
      );

/// Which printer. Printing itself lives in the user's separate printer code
/// (python_parallel_print behind a small print server); this app only sends
/// it the sheet. Choose at build time:
/// - `--dart-define=PRINTER=mock` (default): log only.
/// - `--dart-define=PRINTER=network --dart-define=PRINT_SERVER=http://host:8765`:
///   send each sheet to the print server (default server: localhost:8765).
const String printerChoice = String.fromEnvironment(
  'PRINTER',
  defaultValue: 'mock',
);
const String printServer = String.fromEnvironment(
  'PRINT_SERVER',
  defaultValue: 'http://localhost:8765',
);

PrinterService createPrinter() => printerChoice == 'network'
    ? NetworkPrinterService(server: Uri.parse(printServer))
    : MockPrinterService();

/// A made GIF: its [bytes], and the [file] it was saved as (null if saving
/// failed). The Drive upload reuses the saved file's name.
typedef GuestGif = ({Uint8List bytes, File? file});

/// The guest's GIF: made from [photos] (all 4 captured) and saved into
/// [session] — the one the photos came from, even if the guest has started
/// over by the time it's done. Never throws: returns null if it can't be made
/// (the share screen then hides the GIF panel); a save failure still returns
/// the GIF (with a null [GuestGif.file]) so it can be shown.
Future<GuestGif?> makeAndSaveGif({
  required List<String> photos,
  required Session? session,
  required GifService gifs,
  required SessionService sessions,
}) async {
  if (photos.isEmpty || session == null) return null;
  final Uint8List gif;
  try {
    gif = await gifs.create(photos);
  } catch (error) {
    debugPrint('GIF could not be made: $error');
    return null;
  }
  File? file;
  try {
    file = await sessions.saveGif(gif, session: session);
  } catch (error) {
    debugPrint('GIF could not be saved: $error');
  }
  return (bytes: gif, file: file);
}

enum _Screen { title, camera, selection, print, share }

/// App shell: owns the services and switches screens.
///
/// Port of py-photobooth `ui/main_window.py` (QStackedWidget +
/// `navigate_to_screen`). The camera starts at launch and stays on, like
/// Python; going back to the title resets the session.
class PhotoboothApp extends StatefulWidget {
  const PhotoboothApp({
    super.key,
    required this.camera,
    required this.session,
    required this.sounds,
    required this.catalog,
    required this.composer,
    required this.printer,
    this.gifs = const GifService(),
    this.drive,
  });

  final CameraService camera;
  final SessionService session;
  final SoundService sounds;
  final TemplateCatalog catalog;

  /// Shared, so photo decodes cached while previewing are reused when
  /// printing.
  final CompositeService composer;

  /// Where sheets go: the print server (`PRINTER=network`) or the mock that
  /// only logs (default). See [createPrinter].
  final PrinterService printer;

  /// Makes the guest's GIF from all 4 photos after the camera screen.
  /// Null = feature off (`--dart-define=GIF=off`).
  final GifService? gifs;

  // Null = feature off: nothing is uploaded and no QR is shown.
  final DriveUploadService? drive;

  @override
  State<PhotoboothApp> createState() => _PhotoboothAppState();
}

class _PhotoboothAppState extends State<PhotoboothApp> {
  _Screen _screen = _Screen.title;
  bool _starting = false;
  List<String> _photos = const [];
  Selection? _selection;

  /// This guest's GIF, started when the camera finishes (null = not started).
  Future<Uint8List?>? _gif;

  /// This guest's Drive folder (for the QR code), started when the camera
  /// finishes (null = Drive off).
  Future<DriveFolder?>? _driveFolder;

  /// Whether the last Print was sent (shown on the share screen).
  bool _printed = true;

  @override
  void initState() {
    super.initState();
    unawaited(widget.camera.start());
  }

  @override
  void dispose() {
    unawaited(widget.camera.stop());
    widget.camera.dispose();
    unawaited(widget.sounds.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await widget.session.createSession();
      if (mounted) setState(() => _screen = _Screen.camera);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _toTitle() {
    widget.session.reset();
    widget.composer.clearCache();
    setState(() {
      _photos = const [];
      _selection = null;
      _gif = null;
      _driveFolder = null;
      _screen = _Screen.title;
    });
  }

  Future<void> _toSelection() async {
    final files = await widget.session.listPhotos();
    if (!mounted) return;
    final photos = [for (final f in files) f.path];
    final session = widget.session.current;
    final gifs = widget.gifs;
    final made = gifs == null ? null : _makeGif(photos, session, gifs);
    setState(() {
      _photos = photos;
      // All 4 photos → GIF in the background; ready by the share screen.
      // Null when the GIF feature is off.
      _gif = made?.then((gif) => gif?.bytes);
      _driveFolder = _shareSession(session, made);
      _screen = _Screen.selection;
    });
  }

  Future<GuestGif?> _makeGif(
    List<String> photos,
    Session? session,
    GifService gifs,
  ) => makeAndSaveGif(
    photos: photos,
    session: session,
    gifs: gifs,
    sessions: widget.session,
  );

  /// Folder link for the QR (null = off or failed; never throws). Uploads the
  /// GIF into it in the background once it's ready (if the GIF feature is on).
  Future<DriveFolder?>? _shareSession(
    Session? session,
    Future<GuestGif?>? gif,
  ) {
    final drive = widget.drive;
    if (drive == null || session == null) return null;
    final name = p.basename(session.folder.path); // session_YYYYmmdd_HHMMSS
    if (gif != null) {
      unawaited(() async {
        final made = await gif;
        if (made == null) return;
        try {
          await drive.upload(
            made.bytes,
            // Same name as on disk; the session time if it couldn't be saved.
            name: made.file == null
                ? 'animation_${name.substring(8)}.gif'
                : p.basename(made.file!.path),
            session: name,
            contentType: 'image/gif',
          );
        } catch (error) {
          debugPrint('GIF upload failed: $error');
        }
      }());
    }
    return drive
        .folder(name)
        .then<DriveFolder?>(
          (f) => f,
          onError: (Object e) {
            debugPrint('Drive folder failed: $e');
            return null;
          },
        );
  }

  Future<void> _printSheet(ui.Image sheet, int prints) async {
    final session = widget.session.current;
    final file = await saveAndPrint(
      sheet: sheet,
      prints: prints,
      composer: widget.composer,
      session: widget.session,
      printer: widget.printer,
    );
    final drive = widget.drive;
    if (drive == null || session == null) return;
    unawaited(
      drive
          .upload(
            await file.readAsBytes(),
            name: p.basename(file.path),
            session: p.basename(session.folder.path),
            contentType: 'image/png',
          )
          .then<void>(
            (_) {},
            onError: (Object e) => debugPrint('Upload failed: $e'),
          ),
    );
  }

  Future<ui.Image> _buildPreview(FrameTemplate t, List<String> photos) async {
    final composite = await widget.composer.compose(t, photos);
    try {
      return await widget.composer.previewStrip(composite);
    } finally {
      composite.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Photobooth',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: switch (_screen) {
        _Screen.title => TitleScreen(onStart: _starting ? null : _start),
        _Screen.camera => CameraScreen(
          camera: widget.camera,
          sounds: widget.sounds,
          onPhoto: (photo) =>
              widget.session.savePhoto(photo.bytes, extension: photo.extension),
          onBack: _toTitle,
          onDone: _toSelection,
        ),
        _Screen.selection => SelectionScreen(
          photoPaths: _photos,
          initialSelection: _selection,
          catalog: widget.catalog,
          buildPreview: _buildPreview,
          onNext: (selection) => setState(() {
            _selection = selection;
            _screen = _Screen.print;
          }),
          onStartOver: _toTitle,
        ),
        _Screen.print => PrintScreen(
          buildSheet: () =>
              widget.composer.compose(_selection!.template, _selection!.photos),
          printSheet: _printSheet,
          onBack: () => setState(() => _screen = _Screen.selection),
          onStartOver: _toTitle,
          // Nothing to share (GIF and Drive both off) → the print popup.
          onPrinted: _gif == null && _driveFolder == null
              ? null
              : (printed) => setState(() {
                  _printed = printed;
                  _screen = _Screen.share;
                }),
        ),
        _Screen.share => ShareScreen(
          printed: _printed,
          gif: _gif,
          driveFolder: _driveFolder,
          onDone: _toTitle,
        ),
      },
    );
  }
}
