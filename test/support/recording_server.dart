import 'dart:convert';
import 'dart:io';

/// One request the code under test made.
class RecordedRequest {
  RecordedRequest(this.method, this.uri, this.body);
  final String method;
  final Uri uri;
  final String body;

  String get path => uri.path;
  Map<String, dynamic> get json =>
      body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>;
}

/// A local HTTP server standing in for Supabase (PostgREST + Storage).
/// [respond] picks the JSON answer per request; the default is `[]`.
class RecordingServer {
  late final HttpServer _server;
  final requests = <RecordedRequest>[];

  /// Extra headers on every response, e.g. `content-range: 0-0/1` for
  /// `count: exact` queries.
  final headers = <String, String>{};

  /// Return a (statusCode, jsonBody) for a request, or null for `200 []`.
  (int, Object?)? Function(RecordedRequest request)? respond;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final recorded = RecordedRequest(req.method, req.uri, body);
      requests.add(recorded);
      final answer = respond?.call(recorded);
      req.response.headers.contentType = ContentType.json;
      headers.forEach(req.response.headers.set);
      req.response.statusCode = answer?.$1 ?? 200;
      req.response.write(jsonEncode(answer?.$2 ?? <dynamic>[]));
      await req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);

  RecordedRequest requestTo(String pathSuffix) =>
      requests.lastWhere((r) => r.path.endsWith(pathSuffix));
}
