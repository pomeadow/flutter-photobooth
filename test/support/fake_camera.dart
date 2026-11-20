// Test-only camera (moved out of lib/ — the app always uses a real camera,
// like py-photobooth, which had no fake camera).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_photobooth/services/camera/camera_service.dart';
import 'package:flutter_photobooth/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

/// Camera stand-in for tests — no hardware needed.
///
/// - Default: generates numbered synthetic 1920×1080 PNGs ("Fake photo 1",
///   "Fake photo 2", …) so it works on any machine.
/// - With [photoPaths]: cycles through those files (e.g. real DSLR JPEGs) —
///   handy for testing compositing with realistic photos.
class FakeCameraService extends CameraService {
  FakeCameraService({
    this.photoPaths = const [],
    this.size = const Size(1920, 1080),
    super.warmUp = const Duration(milliseconds: 500),
  });

  final List<String> photoPaths;
  final Size size;
  int _taken = 0;

  /// Number of photos captured so far.
  int get taken => _taken;

  static const _palette = [
    Color(0xFF1E88E5),
    Color(0xFFD81B60),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF00897B),
  ];

  @override
  Future<void> openDevice() async {
    for (final path in photoPaths) {
      if (!File(path).existsSync()) {
        throw CameraException('Fake camera photo not found: $path');
      }
    }
  }

  @override
  Future<void> closeDevice() async {}

  @override
  Future<CapturedPhoto> takePicture() async {
    final n = _taken++;
    if (photoPaths.isNotEmpty) {
      final path = photoPaths[n % photoPaths.length];
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      return CapturedPhoto(
        await File(path).readAsBytes(),
        extension: ext == 'jpeg' ? 'jpg' : ext,
      );
    }
    return CapturedPhoto(await _synthetic(n + 1), extension: 'png');
  }

  @override
  Widget buildPreview(BuildContext context) => _FakePreview(
    colour: _palette[_taken % _palette.length],
    nextPhoto: photoPaths.isEmpty
        ? null
        : photoPaths[_taken % photoPaths.length],
  );

  Future<Uint8List> _synthetic(int number) async {
    final w = size.width;
    final h = size.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final base = _palette[(number - 1) % _palette.length];

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [
          base,
          Color.lerp(base, Colors.black, 0.5)!,
        ]),
    );
    // Corner markers: show cropping in composites (4 corners + centre).
    final marker = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (final c in [
      Offset(w * 0.08, h * 0.12),
      Offset(w * 0.92, h * 0.12),
      Offset(w * 0.08, h * 0.88),
      Offset(w * 0.92, h * 0.88),
    ]) {
      canvas.drawCircle(c, h * 0.04, marker);
    }
    final text = TextPainter(
      text: TextSpan(
        text: 'Fake photo $number',
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontFamilyFallback: AppFonts.fallback,
          color: Colors.white,
          fontSize: h * 0.12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    text.paint(canvas, Offset((w - text.width) / 2, (h - text.height) / 2));

    final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

/// Fake preview: a coloured panel (or the next file photo) with a
/// "FAKE CAMERA" banner, so nobody mistakes it for the real camera.
class _FakePreview extends StatelessWidget {
  const _FakePreview({required this.colour, this.nextPhoto});

  final Color colour;
  final String? nextPhoto;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (nextPhoto != null)
          Image(
            image: ResizeImage(FileImage(File(nextPhoto!)), width: 1280),
            fit: BoxFit.cover,
          )
        else
          ColoredBox(color: colour),
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.black54,
            // Static on purpose: a ticking clock would keep timers alive and
            // make widget tests / pumpAndSettle never settle.
            child: const Text(
              'FAKE CAMERA',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontFamilyFallback: AppFonts.fallback,
                color: Colors.white,
                fontSize: 28,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
