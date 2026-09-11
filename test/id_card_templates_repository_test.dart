import 'dart:typed_data';

import 'package:capstone_dashboard/data/id_card_templates_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_management_module/rfid_management_module.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
      'IdCardTemplatesRepository methods have the expected signatures',
      () {
    final client = SupabaseClient('https://example.supabase.co', 'anon-key');
    final repo = IdCardTemplatesRepository(client);

    Future<List<IdCardTemplateSummary>> Function() fetchTemplates =
        repo.fetchTemplates;
    Future<IdCardTemplateDetail> Function(String) fetchTemplate =
        repo.fetchTemplate;
    Future<String> Function(String) createTemplate = repo.createTemplate;
    Future<void> Function({
      required String id,
      required List<IdCardTemplateElement> frontLayout,
      required List<IdCardTemplateElement> backLayout,
    }) updateTemplateLayouts = repo.updateTemplateLayouts;
    Future<void> Function({required String id, required String name})
        renameTemplate = repo.renameTemplate;
    Future<void> Function(String) deleteTemplate = repo.deleteTemplate;
    Future<String> Function({
      required Uint8List bytes,
      required String fileName,
    }) uploadTemplateImage = repo.uploadTemplateImage;
    Future<String?> Function(String?) fetchTemplateImageUrl =
        repo.fetchTemplateImageUrl;

    expect(fetchTemplates, isNotNull);
    expect(fetchTemplate, isNotNull);
    expect(createTemplate, isNotNull);
    expect(updateTemplateLayouts, isNotNull);
    expect(renameTemplate, isNotNull);
    expect(deleteTemplate, isNotNull);
    expect(uploadTemplateImage, isNotNull);
    expect(fetchTemplateImageUrl, isNotNull);
  });
}
