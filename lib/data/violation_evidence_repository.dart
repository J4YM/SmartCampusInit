import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ViolationEvidenceException implements Exception {
  ViolationEvidenceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A photo picked by the reporter, not yet uploaded.
class EvidenceFile {
  const EvidenceFile({
    required this.name,
    required this.bytes,
    required this.contentType,
  });

  final String name;
  final Uint8List bytes;
  final String contentType;
}

/// Photo evidence for incident reports (private bucket `violation-evidence`,
/// see add_incident_report_classification.sql).
class ViolationEvidenceRepository {
  ViolationEvidenceRepository(this._client);

  final SupabaseClient _client;

  static const bucket = 'violation-evidence';
  static const maxBytes = 5 * 1024 * 1024;
  static const _extensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };

  /// Throws [ViolationEvidenceException] unless [file] is a JPEG/PNG/WebP of
  /// at most 5 MB (the same limits the bucket enforces).
  static void validate(EvidenceFile file) {
    if (!_extensions.containsKey(file.contentType)) {
      throw ViolationEvidenceException(
          '${file.name} is not a photo. Use a JPEG, PNG or WebP image.');
    }
    if (file.bytes.length > maxBytes) {
      throw ViolationEvidenceException('${file.name} is larger than 5 MB.');
    }
  }

  /// Uploads each photo to `<folder>/<uuid>.<ext>` and returns the storage
  /// paths in order.
  Future<List<String>> upload(
    List<EvidenceFile> files, {
    required String folder,
  }) async {
    for (final f in files) {
      validate(f);
    }
    final paths = <String>[];
    try {
      for (final f in files) {
        final path = '$folder/${const Uuid().v4()}.${_extensions[f.contentType]}';
        await _client.storage.from(bucket).uploadBinary(
              path,
              f.bytes,
              fileOptions: FileOptions(contentType: f.contentType),
            );
        paths.add(path);
      }
    } on StorageException catch (e) {
      throw ViolationEvidenceException('Could not upload the photo: ${e.message}');
    }
    return paths;
  }

  /// Short-lived viewing links for staff, keyed by storage path.
  Future<Map<String, String>> signedUrls(List<String> paths) async {
    if (paths.isEmpty) return {};
    try {
      final signed = await _client.storage.from(bucket).createSignedUrls(paths, 3600);
      return {
        for (final s in signed) s.path: s.signedUrl,
      };
    } on StorageException catch (e) {
      throw ViolationEvidenceException('Could not load the photos: ${e.message}');
    }
  }
}
