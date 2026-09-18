// packages/rfid_management_module/lib/ui/id_card_template_list_view.dart
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

class IdCardTemplateSummaryRow {
  const IdCardTemplateSummaryRow({
    required this.id,
    required this.name,
    required this.updatedAtLabel,
  });

  final String id;
  final String name;
  final String updatedAtLabel;
}

/// Lists saved ID card templates — create, open (into the editor),
/// rename, delete. Read-only summary rows; the actual layout is only
/// loaded once the editor opens a specific template (see
/// IdCardTemplateEditorPage).
class IdCardTemplateListView extends StatelessWidget {
  const IdCardTemplateListView({
    super.key,
    required this.templates,
    required this.isLoading,
    required this.onCreate,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<IdCardTemplateSummaryRow> templates;
  final bool isLoading;
  final VoidCallback onCreate;
  final ValueChanged<String> onOpen;
  final void Function(String id, String currentName) onRename;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: BentoCard(
        backgroundColor: ItTechnicianColors.card(context),
        borderColor: ItTechnicianColors.cardBorder(context),
        padding: const EdgeInsets.all(20),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ID Card Templates',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ItTechnicianColors.rowText(context),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Template'),
                style: FilledButton.styleFrom(
                  backgroundColor: ItTechnicianColors.azureBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isLoading)
            SkeletonPulse(
              builder: (context, opacity) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            color: ItTechnicianColors.gray,
                            opacity: opacity,
                            width: 160,
                            height: 13,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            color: ItTechnicianColors.gray,
                            opacity: opacity,
                            width: 110,
                            height: 11,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else if (templates.isEmpty)
            Text(
              'No templates yet — create one to design your first ID card.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ItTechnicianColors.mutedText(context),
              ),
            )
          else
            for (final template in templates)
              _TemplateRow(
                template: template,
                onOpen: () => onOpen(template.id),
                onRename: () => onRename(template.id, template.name),
                onDelete: () => onDelete(template.id),
              ),
        ],
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.template,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final IdCardTemplateSummaryRow template;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ItTechnicianColors.rowText(context),
                    ),
                  ),
                  Text(
                    'Updated ${template.updatedAtLabel}',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: ItTechnicianColors.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Rename',
            onPressed: onRename,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: ItTechnicianColors.dangerRed),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
