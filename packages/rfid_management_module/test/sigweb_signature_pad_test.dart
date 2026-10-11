import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/topaz/topaz_signature_pad.dart';

/// Minimal stand-in for the SigWeb service. Records "VERB /path" per request.
class _FakeSigWeb {
  _FakeSigWeb._(this.server);
  final HttpServer server;
  final requests = <String>[];
  String connectReply = 'true';
  String pointsReply = '42';
  List<int> imageReply = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1];
  int imageStatus = 200;

  static Future<_FakeSigWeb> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeSigWeb._(server);
    server.listen((req) async {
      fake.requests.add('${req.method} ${req.uri.path}');
      final path = req.uri.path.replaceFirst('/SigWeb/', '');
      String? text;
      switch (path) {
        case 'TabletConnectQuery':
          text = fake.connectReply;
        case 'TotalPoints':
          text = fake.pointsReply;
        case 'SigImage/1':
          req.response.statusCode = fake.imageStatus;
          req.response.add(fake.imageReply);
        default:
          text = '';
      }
      if (text != null) req.response.write(text);
      await req.response.close();
    });
    return fake;
  }

  Uri get baseUri =>
      Uri.parse('http://127.0.0.1:${server.port}/SigWeb/');
  Future<void> close() => server.close(force: true);
}

void main() {
  late _FakeSigWeb fake;
  late SigWebSignaturePad pad;

  setUp(() async {
    fake = await _FakeSigWeb.start();
    pad = SigWebSignaturePad(baseUri: fake.baseUri);
  });

  tearDown(() async {
    pad.dispose();
    await fake.close();
  });

  test('isAvailable is true when SigWeb reports a connected tablet', () async {
    expect(await pad.isAvailable(), isTrue);
  });

  test('isAvailable is false when the tablet is not connected', () async {
    fake.connectReply = 'false';
    expect(await pad.isAvailable(), isFalse);
  });

  test('isAvailable is false when SigWeb is not running', () async {
    final dead = SigWebSignaturePad(
      baseUri: Uri.parse('http://127.0.0.1:1/SigWeb/'),
    );
    addTearDown(dead.dispose);
    expect(await dead.isAvailable(), isFalse);
  });

  test('beginCapture configures the image and starts the tablet', () async {
    await pad.beginCapture();
    expect(fake.requests, [
      'POST /SigWeb/Reset',
      'POST /SigWeb/ImageXSize/500',
      'POST /SigWeb/ImageYSize/150',
      'POST /SigWeb/ImagePenWidth/3',
      'POST /SigWeb/JustifyMode/5',
      'GET /SigWeb/ClearSignature',
      'POST /SigWeb/TabletState/1',
    ]);
  });

  test('pointCount parses the plain-text reply', () async {
    expect(await pad.pointCount(), 42);
    fake.pointsReply = 'garbage';
    expect(await pad.pointCount(), 0);
  });

  test('capturePng returns PNG bytes', () async {
    final bytes = await pad.capturePng();
    expect(bytes, isA<Uint8List>());
    expect(bytes.first, 0x89);
  });

  test('capturePng rejects a non-PNG reply', () async {
    fake.imageReply = utf8.encode('not an image at all');
    expect(pad.capturePng(), throwsA(isA<SignaturePadException>()));
  });

  test('capturePng rejects an HTTP error', () async {
    fake.imageStatus = 500;
    expect(pad.capturePng(), throwsA(isA<SignaturePadException>()));
  });

  test('endCapture stops the tablet', () async {
    await pad.endCapture();
    expect(fake.requests.last, 'POST /SigWeb/TabletState/0');
  });
}
