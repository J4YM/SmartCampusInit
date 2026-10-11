import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Returns [png] with its paper turned transparent, so a signature sits on
/// the ID card's own colour instead of in a white box.
///
/// Signatures captured before the pad exported transparent PNGs were saved as
/// black ink on an opaque white background. Each pixel's "ink amount" is how
/// far it is from white (`255 - min(r, g, b)`): pure white becomes fully
/// transparent, solid ink stays solid, and the anti-aliased edge keeps a
/// matching partial alpha (so the stroke stays smooth on any card colour).
///
/// An image that already has transparency is returned untouched, and so is
/// anything that cannot be decoded — this is a cosmetic step and must never
/// lose the signature.
Future<Uint8List> signatureWithTransparentBackground(Uint8List png) async {
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return png;
    final px = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    // Already transparent somewhere: the background was dealt with at capture.
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] < 250) return png;
    }

    final out = Uint8List(px.length);
    for (var i = 0; i < px.length; i += 4) {
      final r = px[i], g = px[i + 1], b = px[i + 2];
      final int alpha = 255 - math.min<int>(r, math.min<int>(g, b));
      if (alpha == 0) continue; // stays 0,0,0,0
      final paper = 255 - alpha;
      out[i] = ((r - paper) * 255 ~/ alpha).clamp(0, 255).toInt();
      out[i + 1] = ((g - paper) * 255 ~/ alpha).clamp(0, 255).toInt();
      out[i + 2] = ((b - paper) * 255 ~/ alpha).clamp(0, 255).toInt();
      out[i + 3] = alpha;
    }

    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        out, image.width, image.height, ui.PixelFormat.rgba8888, done.complete);
    final cleared = await done.future;
    final encoded = await cleared.toByteData(format: ui.ImageByteFormat.png);
    return encoded?.buffer.asUint8List() ?? png;
  } catch (_) {
    return png;
  } finally {
    codec?.dispose();
  }
}
