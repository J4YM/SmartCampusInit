// packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart
import 'package:flutter/material.dart';

import '../id_card_template.dart';

/// Full-screen ID card template editor. This task ships a minimal
/// placeholder body — Task 5 replaces this file's state/build with the
/// real canvas/toolbox/properties-panel editor. The constructor's shape
/// is fixed as of this task: later tasks only change what's inside
/// build()/state (Task 7 adds one more constructor parameter,
/// `onUploadImage` — see that task).
class IdCardTemplateEditorPage extends StatefulWidget {
  const IdCardTemplateEditorPage({
    super.key,
    required this.templateName,
    required this.initialFrontLayout,
    required this.initialBackLayout,
    required this.onSave,
  });

  final String templateName;
  final List<IdCardTemplateElement> initialFrontLayout;
  final List<IdCardTemplateElement> initialBackLayout;

  /// Persists both sides' current element lists. Rethrows on failure so
  /// this page can show the error inline.
  final Future<void> Function(
    List<IdCardTemplateElement> frontLayout,
    List<IdCardTemplateElement> backLayout,
  ) onSave;

  @override
  State<IdCardTemplateEditorPage> createState() =>
      _IdCardTemplateEditorPageState();
}

class _IdCardTemplateEditorPageState extends State<IdCardTemplateEditorPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editing ${widget.templateName}')),
      body: const Center(child: Text('Template editor coming soon.')),
    );
  }
}
