// lib/data/id_card_templates_repository.dart
import 'dart:typed_data';

import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// CRUD for `id_card_templates` plus template-image storage — the ONE
/// shared repository for the template designer, consumed by the template
/// list screen, the editor, and the print flow. Never duplicated
/// per-caller. Defines no types of its own — every type it returns or
/// consumes lives in package:rfid_management_module/id_card_template.dart
/// so the editor UI (in that same package) never needs a second,
/// duplicate model.
class IdCardTemplatesRepository {
  IdCardTemplatesRepository(this._client);
  final SupabaseClient _client;

  static const _templateImagesBucket = 'id-card-template-images';

  Future<List<IdCardTemplateSummary>> fetchTemplates() async {
    final rows = await _client
        .from('id_card_templates')
        .select('id, name, updated_at')
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((row) => IdCardTemplateSummary(
              id: row['id'] as String,
              name: row['name'] as String,
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ))
        .toList();
  }

  Future<IdCardTemplateDetail> fetchTemplate(String id) async {
    final row = await _client
        .from('id_card_templates')
        .select('id, name, front_layout, back_layout')
        .eq('id', id)
        .single();
    return _detailFromRow(row);
  }

  Future<String> createTemplate(String name) async {
    final row = await _client
        .from('id_card_templates')
        .insert({'name': name})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> updateTemplateLayouts({
    required String id,
    required List<IdCardTemplateElement> frontLayout,
    required List<IdCardTemplateElement> backLayout,
  }) async {
    await _client.from('id_card_templates').update({
      'front_layout': frontLayout.map((e) => e.toJson()).toList(),
      'back_layout': backLayout.map((e) => e.toJson()).toList(),
    }).eq('id', id);
  }

  Future<void> renameTemplate({
    required String id,
    required String name,
  }) async {
    await _client
        .from('id_card_templates')
        .update({'name': name}).eq('id', id);
  }

  Future<void> deleteTemplate(String id) async {
    await _client.from('id_card_templates').delete().eq('id', id);
  }

  /// Uploads a static image (e.g. a school logo) for an `image`-type
  /// element and returns its Storage object path. Not tied to a
  /// particular template row — the same uploaded image can be reused by
  /// any element in any template.
  Future<String> uploadTemplateImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final path = '${DateTime.now().microsecondsSinceEpoch}_$fileName';
    await _client.storage.from(_templateImagesBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  /// Resolves [imagePath] to a time-limited signed URL, or null if
  /// [imagePath] is null — mirrors StudentsRepository.fetchStudentPhotoUrl.
  Future<String?> fetchTemplateImageUrl(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;
    return _client.storage
        .from(_templateImagesBucket)
        .createSignedUrl(imagePath, 3600);
  }

  IdCardTemplateDetail _detailFromRow(Map<String, dynamic> row) {
    final frontRaw = row['front_layout'] as List? ?? const [];
    final backRaw = row['back_layout'] as List? ?? const [];
    return IdCardTemplateDetail(
      id: row['id'] as String,
      name: row['name'] as String,
      frontLayout: frontRaw
          .map((e) =>
              IdCardTemplateElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      backLayout: backRaw
          .map((e) =>
              IdCardTemplateElement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
