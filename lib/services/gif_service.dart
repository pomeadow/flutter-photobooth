import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import 'composite_service.dart';

/// How the animated GIF is made.
class GifOptions {
  const GifOptions({
    this.width = 640,
    this.frameDelay = const Duration(milliseconds: 500),
    this.boomerang = false,
    this.loop = true,
  }) : assert(width > 0);

  /// Frame width in pixels; height follows the first photo's aspect ratio.
  final int width;

  /// How long each photo shows. GIF timing is in 1/100 s, so it's rounded.
  final Duration frameDelay;

  /// Play forwards then back (1→4, then 3→2) for a smooth loop.
  final bool boomerang;

  /// Loop forever (otherwise play once).
  final bool loop;
}

/// Makes an animated GIF from a guest's photos. New — py-photobooth had no
/// GIF feature.
///
/// Two stages, so the UI stays smooth:
/// 1. Main isolate, native `dart:ui`: each photo is shrunk while decoding and
///    centre-cropped to one common frame size (GIF frames must match), using
///    the print sheet's crop maths ([CompositeService.coverCrop]).
/// 2. Background isolate (`Isolate.run`): the pure-Dart `image` package
///    quantises to 256 colours and encodes the GIF — the slow part.
///
/// Photos are used as captured (not mirrored), in the order given.
class GifService {
  const GifService();

  /// Encodes [photoPaths] as an animated GIF. Throws [ArgumentError] for an
  /// empty list.
  Future<Uint8List> create(
    List<String> photoPaths, {
    GifOptions options = const GifOptions(),
  }) async {
    if (photoPaths.isEmpty) {
      throw ArgumentError.value(photoPaths, 'photoPaths', 'must not be empty');
    }

    // Frame size from the first photo's shape.
    final firstSize = await _photoSize(photoPaths.first);
    final width = options.width;
    final height = math.max(
      1,
      (width * firstSize.height / firstSize.width).round(),
    );

    final frames = <Uint8List>[
      for (final path in photoPaths) await _frameRgba(path, width, height),
    ];

    final order = [
      for (var i = 0; i < frames.length; i++) i,
      if (options.boomerang && frames.length > 2)
        for (var i = frames.length - 2; i >= 1; i--) i,
    ];
    final delayCs = math.max(
      1,
      (options.frameDelay.inMilliseconds / 10).round(),
    );

    return Isolate.run(
      () => encodeGif(
        frames: frames,
        order: order,
        width: width,
        height: height,
        delayCentiseconds: delayCs,
        loopForever: options.loop,
      ),
    );
  }

  /// Pure-Dart encoding step (runs in the background isolate). [frames] are
  /// RGBA bytes of [width]×[height]; [order] lists frame indices to play.
  static Uint8List encodeGif({
    required List<Uint8List> frames,
    required List<int> order,
    required int width,
    required int height,
    required int delayCentiseconds,
    required bool loopForever,
  }) {
    // repeat 0 = loop forever (NETSCAPE2.0 loop count 0).
    final encoder = img.GifEncoder(delay: delayCentiseconds, repeat: 0);
    final images = [
      for (final rgba in frames)
        img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rgba.buffer,
          numChannels: 4,
        ),
    ];
    for (final i in order) {
      encoder.addFrame(images[i], duration: delayCentiseconds);
    }
    final gif = encoder.finish()!;
    return loopForever ? gif : withoutLoopExtension(gif);
  }

  /// Removes the NETSCAPE2.0 looping block, so the GIF plays once. The
  /// `image` encoder always writes it (any `repeat` value still loops —
  /// e.g. -1 becomes a 65535 loop count); a GIF without it plays once.
  static Uint8List withoutLoopExtension(Uint8List gif) {
    const marker = [0x21, 0xFF, 0x0B]; // extension, application, size 11
    const id = 'NETSCAPE2.0';
    for (var i = 0; i + 19 <= gif.length; i++) {
      if (gif[i] != marker[0] ||
          gif[i + 1] != marker[1] ||
          gif[i + 2] != marker[2]) {
        continue;
      }
      if (String.fromCharCodes(gif, i + 3, i + 14) != id) continue;
      // 3 header + 11 id + 1 sub-block size + 1 sub-id + 2 count + 1 end = 19
      return Uint8List.fromList([...gif.sublist(0, i), ...gif.sublist(i + 19)]);
    }
    return gif;
  }

  static Future<Size> _photoSize(String path) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await File(path).readAsBytes(),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    buffer.dispose();
    return size;
  }

  /// Decodes [path] shrunk to about the frame size, centre-crops it to
  /// exactly [width]×[height], and returns raw RGBA bytes.
  static Future<Uint8List> _frameRgba(
    String path,
    int width,
    int height,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await File(path).readAsBytes(),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.max(
      width / descriptor.width,
      height / descriptor.height,
    );
    final codec = await descriptor.instantiateCodec(
      // Shrink while decoding (never upscale here); keeps aspect ratio.
      targetWidth: scale < 1 ? (descriptor.width * scale).ceil() : null,
    );
    final photo = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();

    try {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        photo,
        CompositeService.coverCrop(
          Size(photo.width.toDouble(), photo.height.toDouble()),
          Size(width.toDouble(), height.toDouble()),
        ),
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final frame = await picture.toImage(width, height);
      picture.dispose();
      try {
        final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
        return rgba!.buffer.asUint8List();
      } finally {
        frame.dispose();
      }
    } finally {
      photo.dispose();
    }
  }
}
