import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A hardware signature pad that can capture a signature as PNG bytes.
///
/// [SignatureCaptureDialog] depends on this interface rather than on Topaz
/// directly, so it can be driven by a fake in tests.
abstract class SignaturePadClient {
  /// Whether the pad (and whatever driver service it needs) is reachable.
  /// Never throws; returns false on any failure.
  Future<bool> isAvailable();

  /// Clears any previous ink and starts listening for pen input.
  Future<void> beginCapture();

  /// Number of pen points captured since [beginCapture] / [clear].
  Future<int> pointCount();

  /// Discards the current ink but keeps capturing.
  Future<void> clear();

  /// Renders the captured signature as PNG bytes.
  Future<Uint8List> capturePng();

  /// Stops listening for pen input.
  Future<void> endCapture();

  /// Releases network resources.
  void dispose();
}

class SignaturePadException implements Exception {
  SignaturePadException(this.message);
  final String message;

  @override
  String toString() => 'SignaturePadException: $message';
}

/// Talks to a Topaz pad (e.g. SigLite T-S460) through the **SigWeb** Windows
/// service, which exposes the pad over a local HTTP API on port 47290
/// (HTTPS) / 47289 (HTTP). Paths and verbs mirror Topaz's `SigWebTablet.js`.
///
/// SigWeb must be installed and running on the PC the pad is plugged into.
/// Uses `package:http`, so it works on Windows and in a browser (the browser
/// reaches the local service the same way Topaz's own JS does).
class SigWebSignaturePad implements SignaturePadClient {
  SigWebSignaturePad({
    Uri? baseUri,
    this.imageWidth = 500,
    this.imageHeight = 150,
    this.penWidth = 3,
    this.timeout = const Duration(seconds: 3),
    http.Client? httpClient,
  })  : baseUri = baseUri ?? defaultBaseUri,
        _client = httpClient ?? http.Client();

  /// `tablet.sigwebtablet.com` resolves to 127.0.0.1 and carries a valid
  /// certificate, which is how Topaz lets HTTPS pages reach the local service.
  static final Uri defaultBaseUri =
      Uri.parse('https://tablet.sigwebtablet.com:47290/SigWeb/');

  /// Must end with a `/`.
  final Uri baseUri;
  final int imageWidth;
  final int imageHeight;
  final int penWidth;
  final Duration timeout;
  final http.Client _client;

  static const _pngSignature = [0x89, 0x50, 0x4E, 0x47];

  @override
  Future<bool> isAvailable() async {
    try {
      final text = await _get('TabletConnectQuery');
      final value = text.trim().replaceAll('"', '').toLowerCase();
      return value == 'true' || value == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> beginCapture() async {
    await _post('Reset');
    await _post('ImageXSize/$imageWidth');
    await _post('ImageYSize/$imageHeight');
    await _post('ImagePenWidth/$penWidth');
    // 5 = scale the ink to fill the output image.
    await _post('JustifyMode/5');
    await _get('ClearSignature');
    await _post('TabletState/1');
  }

  @override
  Future<int> pointCount() async {
    final text = await _get('TotalPoints');
    return int.tryParse(text.trim().replaceAll('"', '')) ?? 0;
  }

  @override
  Future<void> clear() async {
    await _get('ClearSignature');
  }

  @override
  Future<Uint8List> capturePng() async {
    final bytes = await _getBytes('SigImage/1');
    final isPng = bytes.length > _pngSignature.length &&
        List.generate(_pngSignature.length, (i) => bytes[i] == _pngSignature[i])
            .every((ok) => ok);
    if (!isPng) {
      throw SignaturePadException('SigWeb did not return a PNG image.');
    }
    return bytes;
  }

  @override
  Future<void> endCapture() async {
    await _post('TabletState/0');
  }

  @override
  void dispose() => _client.close();

  Uri _uri(String path, {bool noCache = false}) {
    final uri = baseUri.resolve(path);
    if (!noCache) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'noCache': DateTime.now().microsecondsSinceEpoch.toString(),
    });
  }

  Future<String> _get(String path) async =>
      utf8.decode(await _getBytes(path), allowMalformed: true);

  Future<Uint8List> _getBytes(String path) async {
    final response =
        await _client.get(_uri(path, noCache: true)).timeout(timeout);
    return _checked(response, path);
  }

  Future<void> _post(String path) async {
    final response = await _client.post(_uri(path)).timeout(timeout);
    _checked(response, path);
  }

  Uint8List _checked(http.Response response, String path) {
    if (response.statusCode != 200) {
      throw SignaturePadException(
          'SigWeb request "$path" failed (${response.statusCode}).');
    }
    return response.bodyBytes;
  }
}
