// packages/rfid_management_module/lib/ui/id_card_template_list_view.dart
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'shared_form_widgets.dart';

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
class IdCardTemplateListView extends StatefulWidget {
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
  State<IdCardTemplateListView> createState() =>
      _IdCardTemplateListViewState();
}

class _IdCardTemplateListViewState extends State<IdCardTemplateListView> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final templates = widget.templates;
    final pageSize = context.cardPageSize;
    final totalPages =
        templates.isEmpty ? 1 : (templates.length / pageSize).ceil();
    // Clamped, not stored: the list can shrink under the current page (a
    // template deleted, a refresh) without leaving it past the end.
    final currentPage = _page.clamp(1, totalPages);
    final pageTemplates =
        templates.skip((currentPage - 1) * pageSize).take(pageSize).toList();

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
              // Takes the room the button leaves, so a narrow phone cuts the
              // title with an ellipsis instead of overflowing the row.
              Expanded(
                child: Text(
                  'ID Card Templates',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ItTechnicianColors.rowText(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Same pill as Student Records' "Register Student" and Reader
              // Devices' "Add Reader".
              PillButton(
                label: 'New Template',
                icon: Icons.add_rounded,
                onTap: widget.onCreate,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.isLoading)
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
                            color: ItTechnicianColors.gray(context),
                            opacity: opacity,
                            width: 160,
                            height: 13,
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            color: ItTechnicianColors.gray(context),
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
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: ItTechnicianColors.mutedText(context),
              ),
            )
          else ...[
            DashboardTableRows(
              rows: [
                for (final template in pageTemplates)
                  _TemplateRow(
                    key: ValueKey('template-${template.id}'),
                    template: template,
                    onOpen: () => widget.onOpen(template.id),
                    onRename: () =>
                        widget.onRename(template.id, template.name),
                    onDelete: () => widget.onDelete(template.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            CardPaginationFooter(
              currentPage: currentPage,
              totalPages: totalPages,
              totalCount: templates.length,
              textColor: ItTechnicianColors.mutedText(context),
              accentColor: ItTechnicianColors.azureBlue,
              mutedBackground: ItTechnicianColors.background(context),
              onPrevious: () => setState(() => _page = currentPage - 1),
              onNext: () => setState(() => _page = currentPage + 1),
            ),
          ],
        ],
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    super.key,
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
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ItTechnicianColors.rowText(context),
                    ),
                  ),
                  Text(
                    'Updated ${template.updatedAtLabel}',
                    style: GoogleFonts.poppins(
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
