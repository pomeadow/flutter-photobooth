import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../config/templates.dart';

/// Builds print composites and preview strips.
///
/// Port of py-photobooth `controllers/image_processor.py`
/// (`create_photo_composite`, `_resize_photo_to_slot`) and
/// `utils/generate_preview_strips.py`.
///
/// Uses Flutter's native image pipeline (`dart:ui`) rather than a pure-Dart
/// library: decoding/encoding run on engine threads (UI stays responsive) and
/// 6000×4000 camera JPEGs are shrunk *while decoding*.
class CompositeService {
  CompositeService({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  /// Frames are 6×4 in at 300 DPI. Python tagged composites with the first
  /// photo's DPI (350 for the DSLR → wrong print size); always 300 here.
  static const int printDpi = 300;

  final AssetBundle _bundle;
  final Map<String, ui.Image> _frames = {};
  final Map<String, ui.Image> _photos = {};

  /// Full composite: [template]'s frame with [photoPaths] cover-fitted into
  /// its slots, slot `i` getting `photoPaths[i % length]` (Python's rule —
  /// 2 photos fill 4 slots as p1, p2, p1, p2).
  ///
  /// Photos are drawn *over* the frame, as Python pasted them over the slots.
  /// Caller owns the returned image and must `dispose()` it.
  Future<ui.Image> compose(
    FrameTemplate template,
    List<String> photoPaths,
  ) async {
    if (photoPaths.isEmpty) {
      throw ArgumentError.value(photoPaths, 'photoPaths', 'must not be empty');
    }
    final frame = await _frame(template.asset);
    final width = frame.width;
    final height = frame.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.high;

    // White under the frame, so transparent areas print white.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawImage(frame, Offset.zero, paint);

    for (var i = 0; i < template.slots.length; i++) {
      final slot = template.slots[i];
      final photo = await _photo(
        photoPaths[i % photoPaths.length],
        slot.width,
        slot.height,
      );
      canvas.drawImageRect(
        photo,
        coverCrop(
          Size(photo.width.toDouble(), photo.height.toDouble()),
          Size(slot.width.toDouble(), slot.height.toDouble()),
        ),
        Rect.fromLTWH(
          slot.x.toDouble(),
          slot.y.toDouble(),
          slot.width.toDouble(),
          slot.height.toDouble(),
        ),
        paint,
      );
    }

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// Left half of [composite] — what one guest strip looks like after the
  /// print is cut. Python built a second composite from `photos + photos`
  /// first, but `i % length` already repeats photos identically, so the
  /// left half of the real composite is the same image.
  Future<ui.Image> previewStrip(ui.Image composite) async {
    final half = composite.width ~/ 2;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      composite,
      Rect.fromLTWH(0, 0, half.toDouble(), composite.height.toDouble()),
      Rect.fromLTWH(0, 0, half.toDouble(), composite.height.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(half, composite.height);
    } finally {
      picture.dispose();
    }
  }

  /// PNG bytes with a pHYs chunk declaring [dpi] (so 1800×1200 = 6×4 in).
  Future<Uint8List> encodePng(ui.Image image, {int dpi = printDpi}) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return withDpi(data!.buffer.asUint8List(), dpi);
  }

  /// Frees cached decoded frames/photos (Python's `clear_cache`). Call when a
  /// session ends.
  void clearCache() {
    for (final image in [..._frames.values, ..._photos.values]) {
      image.dispose();
    }
    _frames.clear();
    _photos.clear();
  }

  // ---------------------------------------------------------------------------

  Future<ui.Image> _frame(String asset) async {
    final cached = _frames[asset];
    if (cached != null) return cached;
    final data = await _bundle.load(asset);
    return _frames[asset] = await _decode(data.buffer.asUint8List());
  }

  /// Photo decoded at roughly the size needed to cover a [slotW]×[slotH]
  /// slot (never upscaled during decode — drawImageRect handles that).
  Future<ui.Image> _photo(String path, int slotW, int slotH) async {
    final key = '$path|${slotW}x$slotH';
    final cached = _photos[key];
    if (cached != null) return cached;

    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.max(slotW / descriptor.width, slotH / descriptor.height);
    final codec = await descriptor.instantiateCodec(
      // Width only, so the decoder keeps the aspect ratio. Not upscaled.
      targetWidth: scale < 1 ? (descriptor.width * scale).ceil() : null,
    );
    try {
      return _photos[key] = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// Centre crop of an image of [source] size with the aspect ratio of
  /// [slot] — Python's `_resize_photo_to_slot` (scale to cover with
  /// `max(sw/w, sh/h)`, then centre-crop), expressed as a source rectangle.
  static Rect coverCrop(Size source, Size slot) {
    final scale = math.max(
      slot.width / source.width,
      slot.height / source.height,
    );
    final w = slot.width / scale;
    final h = slot.height / scale;
    return Rect.fromLTWH((source.width - w) / 2, (source.height - h) / 2, w, h);
  }

  /// Inserts (or replaces) a PNG `pHYs` chunk declaring [dpi], right after
  /// IHDR. Flutter's PNG encoder writes no DPI.
  static Uint8List withDpi(Uint8List png, int dpi) {
    const ihdrEnd = 8 + 4 + 4 + 13 + 4; // signature + IHDR chunk
    final pixelsPerMetre = (dpi / 0.0254).round();

    final chunk = ByteData(4 + 4 + 9 + 4)
      ..setUint32(0, 9)
      ..setUint8(4, 0x70) // p
      ..setUint8(5, 0x48) // H
      ..setUint8(6, 0x59) // Y
      ..setUint8(7, 0x73) // s
      ..setUint32(8, pixelsPerMetre)
      ..setUint32(12, pixelsPerMetre)
      ..setUint8(16, 1); // unit: metre
    final bytes = chunk.buffer.asUint8List();
    chunk.setUint32(17, _crc32(bytes, 4, 17));

    final rest = _withoutChunk(png.sublist(ihdrEnd), 'pHYs');
    return Uint8List.fromList([...png.sublist(0, ihdrEnd), ...bytes, ...rest]);
  }

  static Uint8List _withoutChunk(Uint8List chunks, String type) {
    final out = BytesBuilder(copy: false);
    final view = ByteData.sublistView(chunks);
    var offset = 0;
    while (offset + 8 <= chunks.length) {
      final length = view.getUint32(offset);
      final end = offset + 12 + length;
      final name = String.fromCharCodes(chunks, offset + 4, offset + 8);
      if (name != type) out.add(chunks.sublist(offset, end));
      offset = end;
    }
    return out.takeBytes();
  }

  static final List<int> _crcTable = List.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(Uint8List data, int start, int end) {
    var crc = 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      crc = _crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}
