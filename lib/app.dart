import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'config/templates.dart';
import 'screens/camera_screen.dart';
import 'screens/print_screen.dart';
import 'screens/selection_screen.dart';
import 'screens/title_screen.dart';
import 'services/camera/camera_service.dart';
import 'services/camera/macos_camera_service.dart';
import 'services/camera/plugin_camera_service.dart';
import 'services/composite_service.dart';
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

enum _Screen { title, camera, selection, print }

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
  });

  final CameraService camera;
  final SessionService session;
  final SoundService sounds;
  final TemplateCatalog catalog;

  /// Shared, so photo decodes cached while previewing are reused when
  /// printing.
  final CompositeService composer;

  /// `MockPrinterService` until a real SELPHY is verified.
  final PrinterService printer;

  @override
  State<PhotoboothApp> createState() => _PhotoboothAppState();
}

class _PhotoboothAppState extends State<PhotoboothApp> {
  _Screen _screen = _Screen.title;
  bool _starting = false;
  List<String> _photos = const [];
  Selection? _selection;

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
      _screen = _Screen.title;
    });
  }

  Future<void> _toSelection() async {
    final files = await widget.session.listPhotos();
    if (!mounted) return;
    setState(() {
      _photos = [for (final f in files) f.path];
      _screen = _Screen.selection;
    });
  }

  Future<void> _printSheet(ui.Image sheet, int prints) => saveAndPrint(
    sheet: sheet,
    prints: prints,
    composer: widget.composer,
    session: widget.session,
    printer: widget.printer,
  );

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
      title: 'OCC Photobooth',
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
        ),
      },
    );
  }
}
