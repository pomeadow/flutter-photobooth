import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'config/templates.dart';
import 'services/composite_service.dart';
import 'services/kiosk_service.dart';
import 'services/printer_service.dart';
import 'services/session_service.dart';
import 'services/sound_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = await SessionService.inDocuments();
  final sounds = SoundService();
  await sounds.load();
  final catalog = await TemplateCatalog.load();

  runApp(
    PhotoboothApp(
      camera: createCamera(),
      session: session,
      sounds: sounds,
      catalog: catalog,
      composer: CompositeService(),
      // Mock until a real Canon SELPHY setup is verified (see README).
      printer: MockPrinterService(),
    ),
  );

  // Full screen + screen always on, in release builds (event devices).
  // `flutter run` stays windowed; override with --dart-define=KIOSK=true.
  if (KioskService.enabledByDefault) unawaited(KioskService().enter());
}
