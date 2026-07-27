import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/discipline_officer_mock_data.dart';
import '../../models/notification_item_model.dart';
import '../../widgets/header_popover_card.dart';
import '../../widgets/logout_confirmation_dialog.dart';
import '../../widgets/notifications_popover.dart';
import '../../widgets/settings_popover.dart';
import '../profile/profile_screen.dart';

// ---------------------------------------------------------------------------
// Data models — Supabase (`discipline_cases`) ready.
// fromJson()/toJson() map directly onto snake_case Postgres columns so rows
// can be streamed straight into these models once the backend is wired up.
// ---------------------------------------------------------------------------

class DisciplineSummaryMetricsModel {
  const DisciplineSummaryMetricsModel({
    this.pendingQueueCount = 0,
    this.escalatedCount = 0,
    this.processedTodayCount = 0,
    this.avgResponseTimeMinutes = 0.0,
  });

  final int pendingQueueCount;
  final int escalatedCount;
  final int processedTodayCount;
  final double avgResponseTimeMinutes;

  factory DisciplineSummaryMetricsModel.fromJson(Map<String, dynamic> json) {
    return DisciplineSummaryMetricsModel(
      pendingQueueCount: json['pending_queue_count'] as int? ?? 0,
      escalatedCount: json['escalated_count'] as int? ?? 0,
      processedTodayCount: json['processed_today_count'] as int? ?? 0,
      avgResponseTimeMinutes:
          (json['avg_response_time_minutes'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pending_queue_count': pendingQueueCount,
      'escalated_count': escalatedCount,
      'processed_today_count': processedTodayCount,
      'avg_response_time_minutes': avgResponseTimeMinutes,
    };
  }
}

class DisciplineCaseModel {
  const DisciplineCaseModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.programGradeSection,
    required this.violationType,
    this.isEscalated = false,
    this.slaRemaining,
    required this.submittedBy,
    required this.incidentLocation,
    required this.incidentDateTime,
    this.priorViolationsCount = 0,
    required this.description,
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String programGradeSection;
  final String violationType;
  final bool isEscalated;

  /// Countdown label as supplied by the backend, e.g. `"02:20"`. `null` means
  /// no SLA deadline is attached to this case.
  final String? slaRemaining;
  final String submittedBy;
  final String incidentLocation;
  final DateTime incidentDateTime;
  final int priorViolationsCount;
  final String description;

  factory DisciplineCaseModel.fromJson(Map<String, dynamic> json) {
    return DisciplineCaseModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentNumber: json['student_number'] as String,
      programGradeSection: json['program_grade_section'] as String,
      violationType: json['violation_type'] as String,
      isEscalated: json['is_escalated'] as bool? ?? false,
      slaRemaining: json['sla_remaining'] as String?,
      submittedBy: json['submitted_by'] as String,
      incidentLocation: json['incident_location'] as String,
      incidentDateTime: DateTime.parse(json['incident_datetime'] as String),
      priorViolationsCount: json['prior_violations_count'] as int? ?? 0,
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'student_number': studentNumber,
      'program_grade_section': programGradeSection,
      'violation_type': violationType,
      'is_escalated': isEscalated,
      'sla_remaining': slaRemaining,
      'submitted_by': submittedBy,
      'incident_location': incidentLocation,
      'incident_datetime': incidentDateTime.toIso8601String(),
      'prior_violations_count': priorViolationsCount,
      'description': description,
    };
  }
}

/// One selectable row in the Modify dialog's offense dropdown — a
/// `handbook_offenses` row reduced to what the UI needs to display and
/// persist a selection.
class OffenseOption {
  const OffenseOption({
    required this.id,
    required this.label,
    this.category,
  });

  final String id;

  /// `handbook_offenses.description` — the human-readable offense title.
  final String label;

  /// `handbook_offenses.category` (e.g. "Minor", "Major_A"), shown as a
  /// hint alongside [label]. Null for the built-in demo list.
  final String? category;
}

// NotificationItemModel moved to models/notification_item_model.dart —
// shared verbatim with every other module.

class GoodMoralRequestModel {
  const GoodMoralRequestModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.programGradeSection,
    required this.documentType,
    required this.purpose,
    required this.requestedBy,
    required this.requestDateTime,
    this.remarks = '',
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String programGradeSection;

  /// e.g. "Good Moral Certificate", "Certificate of Clearance".
  final String documentType;

  /// e.g. "Employment", "Scholarship application", "School transfer".
  final String purpose;
  final String requestedBy;
  final DateTime requestDateTime;
  final String remarks;

  factory GoodMoralRequestModel.fromJson(Map<String, dynamic> json) {
    return GoodMoralRequestModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentNumber: json['student_number'] as String,
      programGradeSection: json['program_grade_section'] as String,
      documentType: json['document_type'] as String,
      purpose: json['purpose'] as String,
      requestedBy: json['requested_by'] as String,
      requestDateTime: DateTime.parse(json['request_datetime'] as String),
      remarks: json['remarks'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'student_number': studentNumber,
      'program_grade_section': programGradeSection,
      'document_type': documentType,
      'purpose': purpose,
      'requested_by': requestedBy,
      'request_datetime': requestDateTime.toIso8601String(),
      'remarks': remarks,
    };
  }
}

/// Master directory entry for an enrolled student — independent of any
/// pending Good Moral request. Supabase (`students`) ready.
class StudentDirectoryEntryModel {
  const StudentDirectoryEntryModel({
    required this.id,
    required this.studentName,
    required this.studentNumber,
    required this.programGradeSection,
    this.status = 'Enrolled',
  });

  final String id;
  final String studentName;
  final String studentNumber;
  final String programGradeSection;
  final String status;

  factory StudentDirectoryEntryModel.fromJson(Map<String, dynamic> json) {
    return StudentDirectoryEntryModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      studentNumber: json['student_number'] as String,
      programGradeSection: json['program_grade_section'] as String,
      status: json['status'] as String? ?? 'Enrolled',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'student_number': studentNumber,
      'program_grade_section': programGradeSection,
      'status': status,
    };
  }
}

/// Unifies a queued [GoodMoralRequestModel] and a plain
/// [StudentDirectoryEntryModel] into the one shape the Preview panel needs —
/// either the Requests queue or the Students List directory can populate the
/// selection, and the panel shouldn't care which one it came from.
class GoodMoralSelectedStudent {
  const GoodMoralSelectedStudent({
    required this.sourceId,
    required this.sourceSubTab,
    required this.studentName,
    required this.studentNumber,
    required this.programGradeSection,
    this.documentType,
    this.purpose,
    this.requestedBy,
    this.requestDateTime,
    this.remarks = '',
  });

  /// The originating [GoodMoralRequestModel.id] or
  /// [StudentDirectoryEntryModel.id] — lets a list tile tell whether *it* is
  /// the current selection without caring about the other list.
  final String sourceId;
  final GoodMoralSubTab sourceSubTab;

  final String studentName;
  final String studentNumber;
  final String programGradeSection;
  final String? documentType;
  final String? purpose;
  final String? requestedBy;
  final DateTime? requestDateTime;
  final String remarks;

  factory GoodMoralSelectedStudent.fromRequest(GoodMoralRequestModel request) {
    return GoodMoralSelectedStudent(
      sourceId: request.id,
      sourceSubTab: GoodMoralSubTab.requests,
      studentName: request.studentName,
      studentNumber: request.studentNumber,
      programGradeSection: request.programGradeSection,
      documentType: request.documentType,
      purpose: request.purpose,
      requestedBy: request.requestedBy,
      requestDateTime: request.requestDateTime,
      remarks: request.remarks,
    );
  }

  factory GoodMoralSelectedStudent.fromDirectoryEntry(
    StudentDirectoryEntryModel student,
  ) {
    return GoodMoralSelectedStudent(
      sourceId: student.id,
      sourceSubTab: GoodMoralSubTab.studentsList,
      studentName: student.studentName,
      studentNumber: student.studentNumber,
      programGradeSection: student.programGradeSection,
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard tab navigation state
// ---------------------------------------------------------------------------

enum DashboardTab { violations, goodMoral, report, parentalIntervention }

/// Tracks which top-level dashboard view is active. A thin [ValueNotifier]
/// (same pattern as the app's `themeModeController`) so `DashboardHeaderNavBar`
/// and the page body can both react without threading a raw enum + setState
/// callback pair through the widget tree by hand.
class DashboardTabController extends ValueNotifier<DashboardTab> {
  DashboardTabController([super.initialTab = DashboardTab.violations]);

  void selectViolations() => value = DashboardTab.violations;

  void selectGoodMoral() => value = DashboardTab.goodMoral;

  void selectReport() => value = DashboardTab.report;

  void selectParentalIntervention() =>
      value = DashboardTab.parentalIntervention;
}

// ---------------------------------------------------------------------------
// Good Moral Management — sub-tab navigation + state controller
// ---------------------------------------------------------------------------

/// Which queue is showing in the Good Moral Management left panel.
enum GoodMoralSubTab { requests, studentsList }

/// Owns every piece of state behind the Good Moral Management view: which
/// sub-tab (Requests / Students List) is active, the two source lists, and
/// the single selection shared by both — since either list can populate the
/// Preview panel on the right, selection lives here rather than in either
/// list's own widget.
class GoodMoralDashboardController extends ChangeNotifier {
  GoodMoralSubTab _activeSubTab = GoodMoralSubTab.requests;
  GoodMoralSubTab get activeSubTab => _activeSubTab;

  List<GoodMoralRequestModel> _requests = const [];
  List<GoodMoralRequestModel> get requests => _requests;

  List<StudentDirectoryEntryModel> _students = const [];
  List<StudentDirectoryEntryModel> get students => _students;

  GoodMoralSelectedStudent? _selectedStudentRequest;
  GoodMoralSelectedStudent? get selectedStudentRequest =>
      _selectedStudentRequest;

  /// True when nothing is selected — drives the Preview panel's empty state
  /// and disables the "Generate & Print Certificate" action.
  bool get isEmptyState => _selectedStudentRequest == null;

  void selectSubTab(GoodMoralSubTab tab) {
    if (_activeSubTab == tab) return;
    _activeSubTab = tab;
    notifyListeners();
  }

  void selectRequest(GoodMoralRequestModel request) {
    _selectedStudentRequest = GoodMoralSelectedStudent.fromRequest(request);
    notifyListeners();
  }

  void selectStudent(StudentDirectoryEntryModel student) {
    _selectedStudentRequest = GoodMoralSelectedStudent.fromDirectoryEntry(
      student,
    );
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedStudentRequest == null) return;
    _selectedStudentRequest = null;
    notifyListeners();
  }

  void setRequests(List<GoodMoralRequestModel> requests) {
    _requests = requests;
    notifyListeners();
  }

  void setStudents(List<StudentDirectoryEntryModel> students) {
    _students = students;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _DashboardColors {
  static const headerBackground = Color(0xFF15253F);
  static const headerBorder = Color(0x1AFFFFFF);
  static const surfaceBackground = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const emptyStateIcon = Color(0xFFCBD5E1);

  // Navy top-bar chrome (icon avatar + bell button backdrop).
  static const metricCardBackground = Color(0x14FFFFFF);

  // Light metric-card row beneath the navy top bar.
  static const metricCardBg = Color(0xFFFFFFFF);
  static const metricCardLightBorder = Color(0xFFE2E8F0);
  static const metricLabelMuted = Color(0xFF64748B);
  static const metricIconMuted = Color(0xFF94A3B8);
  static const metricValueDark = Color(0xFF1E293B);

  static const queueHeaderStart = Color(0xFF2563EB);

  static const escalatedRowBackground = Color(0xFFFEF2F2);
  static const escalatedBadgeBg = Color(0xFFDC2626);
  static const slaBadgeBg = Color(0xFFDC2626);

  static const priorViolationBadgeBg = Color(0xFFFEE2E2);
  static const priorViolationBadgeText = Color(0xFFDC2626);

  static const warningBannerBg = Color(0xFFFEF2F2);
  static const warningBannerBorder = Color(0xFFFECACA);
  static const warningBannerText = Color(0xFFDC2626);

  static const slaDeadlineBadgeBg = Color(0xFFF59E0B);

  static const validateGreen = Color(0xFF10B981);
  static const validateMuted = Color(0xFFA7F3D0);
  static const modifyBlue = Color(0xFF2563EB);
  static const modifyMuted = Color(0xFFBFDBFE);
  static const denyRed = Color(0xFFDC2626);
  static const denyMuted = Color(0xFFFECACA);

  // Good Moral Requests/Students List sub-tabs — pill button style.
  static const activeTabColor = Color(0xFF345892);
  static const inactiveTabColor = Color(0xFFF4F4F4);
  static const inactiveTabText = Color(0xFF1E293B);
  static const inactiveTabBorder = Color(0x1A000000); // black @ 10% opacity

  // Top-level DashboardHeaderNavBar (Violations / Good Moral / Report /
  // Parental Intervention) — flat underline-tab style.
  static const navBarBackground = Color(0xFFFFFFFF);
  static const navBarBorder = Color(0xFFE2E8F0);
  static const navBarActiveText = Color(0xFF345892);
  static const navBarInactiveText = Color(0xFF8F8F8F);
  static const navBarIndicator = Color(0xFF345892);

  // Good Moral Management preview panel — "Generate & Print Certificate".
  static const goodMoralButtonMuted = Color(0xFF93C5FD);
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

const _monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatFullDateTime(DateTime dateTime) {
  final month = _monthAbbreviations[dateTime.month - 1];
  final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '$month ${dateTime.day}, ${dateTime.year}, $hour12:$minute $period';
}

String _timeAgoLabel(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

String _formatAvgResponseTime(double minutes) {
  final totalSeconds = (minutes * 60).round();
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m}m ${s}s';
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class DisciplineOfficerDashboardPage extends StatefulWidget {
  const DisciplineOfficerDashboardPage({
    super.key,
    this.onReturnToHub,
    this.onSignOut,
  });

  /// Set when Admin opens this page from the hub as a preview; renders a
  /// back button in the header. Null for a Discipline Officer's own direct
  /// login route, where there is no hub to return to.
  final VoidCallback? onReturnToHub;

  /// Renders a sign-out action in the header when set — required for the
  /// direct-login route (no hub app bar to sign out from otherwise).
  final VoidCallback? onSignOut;

  @override
  State<DisciplineOfficerDashboardPage> createState() =>
      _DisciplineOfficerDashboardPageState();
}

class _DisciplineOfficerDashboardPageState
    extends State<DisciplineOfficerDashboardPage> {
  // Light/dark theme state — flipped directly by the Settings popover's
  // Dark Mode switch. Owned locally (rather than by a root MaterialApp,
  // like the source repo's standalone build did) since this page is
  // embedded inside the host app's own MaterialApp.
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

  // Backend-ready state, seeded from DisciplineOfficerMockData for now.
  // Replace these initializers with a Supabase realtime subscription / query
  // result once the API layer exists.
  DisciplineSummaryMetricsModel metrics =
      DisciplineOfficerMockData.getSummaryMetrics();
  final List<DisciplineCaseModel> pendingQueue =
      DisciplineOfficerMockData.getPendingViolations();
  DisciplineCaseModel? selectedCase;
  final List<NotificationItemModel> notifications = <NotificationItemModel>[];

  final tabController = DashboardTabController();
  final goodMoralController = GoodMoralDashboardController();

  @override
  void initState() {
    super.initState();
    goodMoralController.setRequests(
      DisciplineOfficerMockData.getGoodMoralRequests(),
    );
    goodMoralController.setStudents(
      DisciplineOfficerMockData.getStudentDirectory(),
    );
  }

  @override
  void dispose() {
    _themeMode.dispose();
    tabController.dispose();
    goodMoralController.dispose();
    super.dispose();
  }

  void _selectCase(DisciplineCaseModel caseItem) {
    setState(() => selectedCase = caseItem);
  }

  void _resolveSelectedCase() {
    final resolved = selectedCase;
    if (resolved == null) return;

    setState(() {
      pendingQueue.removeWhere((c) => c.id == resolved.id);
      selectedCase = null;
      metrics = DisciplineSummaryMetricsModel(
        pendingQueueCount: pendingQueue.length,
        escalatedCount: pendingQueue.where((c) => c.isEscalated).length,
        processedTodayCount: metrics.processedTodayCount + 1,
        avgResponseTimeMinutes: metrics.avgResponseTimeMinutes,
      );
    });

    // TODO(supabase): persist the resolution (approve/modify/deny) to the
    // `discipline_cases` table and let the realtime subscription reconcile
    // `pendingQueue` instead of mutating local state directly.
  }

  void _handleValidate() => _resolveSelectedCase();

  void _handleModify() => _resolveSelectedCase();

  void _handleDeny() => _resolveSelectedCase();

  void _handleGenerateCertificate() {
    // TODO(supabase): render + persist the certificate PDF for
    // `goodMoralController.selectedStudentRequest` against the
    // `good_moral_requests` table, then hand off to print.
  }

  void _markAllNotificationsRead() {
    setState(() {
      for (var i = 0; i < notifications.length; i++) {
        notifications[i] = notifications[i].copyWith(isRead: true);
      }
    });
  }

  /// Thin wrapper around the shared [showHeaderPopover] so every call site
  /// below reads the same as before the popovers were extracted into
  /// `widgets/`.
  Future<void> _showHeaderPopover({
    required Widget Function(BuildContext context, StateSetter setPopoverState)
        contentBuilder,
  }) {
    return showHeaderPopover(context: context, contentBuilder: contentBuilder);
  }

  void _openSettings() {
    _showHeaderPopover(
      contentBuilder: (popoverContext, setPopoverState) {
        return SettingsPopover(
          themeModeController: _themeMode,
        );
      },
    );
  }

  void _openProfile() {
    _showHeaderPopover(
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          onViewProfile: () {
            Navigator.of(popoverContext).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
          },
          onLogout: () {
            Navigator.of(popoverContext).pop();
            _confirmLogout();
          },
        );
      },
    );
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return LogoutConfirmationDialog(
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            widget.onSignOut?.call();
          },
        );
      },
    );
  }

  void _showNotificationsMenu() {
    _showHeaderPopover(
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: notifications,
          onMarkAllRead: () {
            _markAllNotificationsRead();
            setPopoverState(() {});
          },
          onViewAll: () => Navigator.of(popoverContext).pop(),
          // TODO(supabase): route to a dedicated notifications page
          // backed by a `notifications` table once it exists.
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, child) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: _DashboardColors.headerBackground,
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ),
          child: child!,
        );
      },
      child: Scaffold(
        backgroundColor: _DashboardColors.surfaceBackground,
        body: Column(
          children: [
            AppHeaderNavBar(
              title: 'Discipline Officer Dashboard',
              subtitle: 'Mission Control Center',
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onReturnToHub != null) ...[
                    HeaderIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: widget.onReturnToHub!,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _DashboardColors.metricCardBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _DashboardColors.headerBorder),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
              actions: [
                HeaderIconButton(
                  icon: Icons.notifications_none_rounded,
                  badgeCount: notifications.where((n) => !n.isRead).length,
                  onTap: _showNotificationsMenu,
                ),
                HeaderIconButton(
                  icon: Icons.settings_outlined,
                  onTap: _openSettings,
                ),
                ProfileAvatarButton(onTap: _openProfile),
                if (widget.onSignOut != null)
                  HeaderIconButton(
                    icon: Icons.logout_rounded,
                    onTap: widget.onSignOut!,
                  ),
              ],
            ),
            // Tab bar + main content share the same 1440px-capped, centered
            // frame every dashboard module uses (see DashboardPageWrapper).
            Expanded(
              child: DashboardPageWrapper(
                child: ValueListenableBuilder<DashboardTab>(
                  valueListenable: tabController,
                  builder: (context, activeTab, _) {
                    return Column(
                      children: [
                        DashboardHeaderNavBar(
                          activeTab: activeTab,
                          onTabSelected: (tab) => tabController.value = tab,
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Column(
                            children: [
                              if (activeTab == DashboardTab.violations) ...[
                                _MetricsRow(metrics: metrics),
                                const SizedBox(height: 20),
                              ],
                              Expanded(child: _buildTabContent(activeTab)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(DashboardTab activeTab) {
    return switch (activeTab) {
      DashboardTab.violations => _buildViolationsContent(),
      DashboardTab.goodMoral => _buildGoodMoralContent(),
      DashboardTab.report => const _EmptySectionView(
          icon: Icons.fact_check_outlined,
          title: 'Report',
          subtitle: 'CHED reporting is not available yet',
        ),
      DashboardTab.parentalIntervention => const _EmptySectionView(
          icon: Icons.groups_outlined,
          title: 'Parental Intervention',
          subtitle: 'Parental intervention records are not available yet',
        ),
    };
  }

  Widget _buildViolationsContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 900;

        final queueCard = _ApprovalQueueCard(
          cases: pendingQueue,
          selectedCaseId: selectedCase?.id,
          onSelect: _selectCase,
        );

        final detailsPanel = _IncidentDetailsPanel(
          selectedCase: selectedCase,
          onValidate: _handleValidate,
          onModify: _handleModify,
          onDeny: _handleDeny,
        );

        if (stackColumns) {
          return Column(
            children: [
              Expanded(flex: 4, child: queueCard),
              const SizedBox(height: 16),
              Expanded(flex: 6, child: detailsPanel),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: queueCard),
            const SizedBox(width: 16),
            Expanded(flex: 7, child: detailsPanel),
          ],
        );
      },
    );
  }

  Widget _buildGoodMoralContent() {
    return GoodMoralManagementView(
      controller: goodMoralController,
      onGenerateCertificate: _handleGenerateCertificate,
    );
  }
}

// ---------------------------------------------------------------------------
// Empty placeholder section (Report / Parental Intervention)
// ---------------------------------------------------------------------------

/// Generic "nothing here yet" section for tabs that don't have a data model
/// or workflow defined yet. Mirrors the visual language of the queue/detail
/// empty states (rounded-square icon badge, title, subtitle) so a bare tab
/// doesn't look broken while its real content is built out.
class _EmptySectionView extends StatelessWidget {
  const _EmptySectionView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _DashboardColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _DashboardColors.cardBorder),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 32,
                color: _DashboardColors.emptyStateIcon,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _DashboardColors.primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _DashboardColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top-level header navigation bar (Violations / Good Moral / Report /
// Parental Intervention)
// ---------------------------------------------------------------------------

/// Full-width underline-tab bar rendered directly below [_DashboardHeader]
/// and above the padded content area. Distinct from [_DashboardTabButton]
/// (the pill-style buttons used by the Good Moral Requests/Students List
/// sub-tabs), which keeps its own filled-background look.
class DashboardHeaderNavBar extends StatelessWidget {
  const DashboardHeaderNavBar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  final DashboardTab activeTab;
  final ValueChanged<DashboardTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _DashboardColors.navBarBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _DashboardColors.navBarBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        // Stretch so every _DashboardNavBarItem spans the bar's full 52px
        // height, letting its indicator's Positioned(bottom: 0) land flush
        // on the container's own bottom edge (on top of navBarBorder)
        // instead of being inset by the row's own vertical centering.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashboardNavBarItem(
            label: 'Violations',
            isActive: activeTab == DashboardTab.violations,
            onTap: () => onTabSelected(DashboardTab.violations),
          ),
          const SizedBox(width: 28),
          _DashboardNavBarItem(
            label: 'Good Moral',
            isActive: activeTab == DashboardTab.goodMoral,
            onTap: () => onTabSelected(DashboardTab.goodMoral),
          ),
          const SizedBox(width: 28),
          _DashboardNavBarItem(
            label: 'Report',
            isActive: activeTab == DashboardTab.report,
            onTap: () => onTabSelected(DashboardTab.report),
          ),
          const SizedBox(width: 28),
          _DashboardNavBarItem(
            label: 'Parental Intervention',
            isActive: activeTab == DashboardTab.parentalIntervention,
            onTap: () => onTabSelected(DashboardTab.parentalIntervention),
          ),
        ],
      ),
    );
  }
}

class _DashboardNavBarItem extends StatelessWidget {
  const _DashboardNavBarItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Stack(
        // No padding/margin wrapping this Stack: it takes the item's full
        // stretched height from the parent Row, so `bottom: 0` below is the
        // container's actual bottom edge, not an inset placeholder.
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? _DashboardColors.navBarActiveText
                    : _DashboardColors.navBarInactiveText,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: isActive
                    ? _DashboardColors.navBarIndicator
                    : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTabButton extends StatelessWidget {
  const _DashboardTabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive
          ? _DashboardColors.activeTabColor
          : _DashboardColors.inactiveTabColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isActive
            ? BorderSide.none
            : const BorderSide(
                color: _DashboardColors.inactiveTabBorder,
                width: 1,
              ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    isActive ? Colors.white : _DashboardColors.inactiveTabText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics bar
// ---------------------------------------------------------------------------

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.metrics});

  final DisciplineSummaryMetricsModel metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final metricCards = [
          _MetricCard(
            label: 'Pending Queue',
            value: '${metrics.pendingQueueCount}',
            icon: Icons.access_time_rounded,
          ),
          _MetricCard(
            label: 'Escalated',
            value: '${metrics.escalatedCount}',
            icon: Icons.shield_outlined,
          ),
          _MetricCard(
            label: 'Processed Today',
            value: '${metrics.processedTodayCount}',
            icon: Icons.check_circle_outline_rounded,
          ),
          _MetricCard(
            label: 'Avg Response',
            value: _formatAvgResponseTime(metrics.avgResponseTimeMinutes),
            icon: Icons.trending_up_rounded,
          ),
        ];

        if (isNarrow) {
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: metricCards
                .map((c) => SizedBox(width: 260, height: 88, child: c))
                .toList(),
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in metricCards) ...[
                Expanded(child: card),
                if (card != metricCards.last) const SizedBox(width: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}

// Shared header-dropdown chrome (HeaderPopoverCard / PopoverHeaderBar) moved
// to widgets/header_popover_card.dart. Settings dropdown moved to
// widgets/settings_popover.dart. Both are shared verbatim with every other
// module.

// ---------------------------------------------------------------------------
// Account popover — anchored below the header's profile avatar.
// ---------------------------------------------------------------------------

class AccountProfileMenu extends StatelessWidget {
  const AccountProfileMenu({
    super.key,
    required this.onViewProfile,
    required this.onLogout,
  });

  final VoidCallback onViewProfile;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return HeaderPopoverCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Account',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF000000),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: _DashboardColors.cardBorder),
          _AccountMenuItem(label: 'View profile', onTap: onViewProfile),
          const Divider(height: 1, color: _DashboardColors.cardBorder),
          _AccountMenuItem(label: 'Logout', onTap: onLogout),
        ],
      ),
    );
  }
}

class _AccountMenuItem extends StatelessWidget {
  const _AccountMenuItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF4A4A4A),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _DashboardColors.metricCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _DashboardColors.metricCardLightBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _DashboardColors.metricLabelMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: _DashboardColors.metricValueDark,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: _DashboardColors.metricIconMuted, size: 20),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column — Approval Queue
// ---------------------------------------------------------------------------

class _ApprovalQueueCard extends StatefulWidget {
  const _ApprovalQueueCard({
    required this.cases,
    required this.selectedCaseId,
    required this.onSelect,
  });

  final List<DisciplineCaseModel> cases;
  final String? selectedCaseId;
  final ValueChanged<DisciplineCaseModel> onSelect;

  @override
  State<_ApprovalQueueCard> createState() => _ApprovalQueueCardState();
}

class _ApprovalQueueCardState extends State<_ApprovalQueueCard> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DisciplineCaseModel> get _filteredCases {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.cases;

    return widget.cases.where((c) {
      return c.studentName.toLowerCase().contains(query) ||
          c.studentNumber.toLowerCase().contains(query) ||
          c.violationType.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCases = _filteredCases;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _DashboardColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _DashboardColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _DashboardColors.cardBorder),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Approval Queue',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _DashboardColors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.cases.length} pending slips · Oldest first',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _DashboardColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: _QueueSearchField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: filteredCases.isEmpty
                ? const _QueueEmptyState()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: filteredCases.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      color: _DashboardColors.cardBorder,
                    ),
                    itemBuilder: (context, index) {
                      final caseItem = filteredCases[index];
                      return _QueueCaseTile(
                        caseItem: caseItem,
                        isSelected: caseItem.id == widget.selectedCaseId,
                        onTap: () => widget.onSelect(caseItem),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueSearchField extends StatelessWidget {
  const _QueueSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: GoogleFonts.poppins(
        fontSize: 13,
        color: _DashboardColors.primaryText,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search',
        hintStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: const Color(0xFF94A3B8),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: Color(0xFF94A3B8),
        ),
        filled: true,
        fillColor: _DashboardColors.surfaceBackground,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _QueueEmptyState extends StatelessWidget {
  const _QueueEmptyState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 48,
                    color: _DashboardColors.emptyStateIcon,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No pending approval slips',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QueueCaseTile extends StatelessWidget {
  const _QueueCaseTile({
    required this.caseItem,
    required this.isSelected,
    required this.onTap,
  });

  final DisciplineCaseModel caseItem;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: caseItem.isEscalated
              ? _DashboardColors.escalatedRowBackground
              : (isSelected ? const Color(0xFFEFF6FF) : Colors.transparent),
          border: Border(
            left: BorderSide(
              width: 3,
              color: caseItem.isEscalated
                  ? _DashboardColors.escalatedBadgeBg
                  : (isSelected
                      ? _DashboardColors.queueHeaderStart
                      : Colors.transparent),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: caseItem.isEscalated
                      ? const _EscalatedBadge()
                      : const SizedBox.shrink(),
                ),
                if (caseItem.slaRemaining != null)
                  _SlaChip(label: caseItem.slaRemaining!),
              ],
            ),
            if (caseItem.isEscalated) const SizedBox(height: 8),
            Text(
              caseItem.studentName,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _DashboardColors.primaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${caseItem.violationType}\n'
              '${caseItem.programGradeSection} · ${_timeAgoLabel(caseItem.incidentDateTime)}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.4,
                color: _DashboardColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'By: ${caseItem.submittedBy}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                ),
                if (caseItem.priorViolationsCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _DashboardColors.priorViolationBadgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${caseItem.priorViolationsCount} prior violation'
                      '${caseItem.priorViolationsCount == 1 ? '' : 's'}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _DashboardColors.priorViolationBadgeText,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EscalatedBadge extends StatelessWidget {
  const _EscalatedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _DashboardColors.escalatedBadgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            'ESCALATED',
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlaChip extends StatelessWidget {
  const _SlaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _DashboardColors.slaBadgeBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column — Incident Details Panel
// ---------------------------------------------------------------------------

class _IncidentDetailsPanel extends StatelessWidget {
  const _IncidentDetailsPanel({
    required this.selectedCase,
    required this.onValidate,
    required this.onModify,
    required this.onDeny,
  });

  final DisciplineCaseModel? selectedCase;
  final VoidCallback onValidate;
  final VoidCallback onModify;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final caseItem = selectedCase;

    return Container(
      decoration: BoxDecoration(
        color: _DashboardColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _DashboardColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caseItem?.violationType ?? 'No Case Selected',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _DashboardColors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        caseItem == null
                            ? 'Select a slip from the approval queue'
                            : 'Submitted ${_timeAgoLabel(caseItem.incidentDateTime)}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: _DashboardColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                _SlaDeadlineBadge(label: caseItem?.slaRemaining),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: caseItem == null
                ? const _DetailsEmptyState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (caseItem.isEscalated) ...[
                          const _SecurityWarningBanner(),
                          const SizedBox(height: 16),
                        ],
                        const _DetailSectionHeader(
                          icon: Icons.person_outline,
                          title: 'Student Information',
                        ),
                        const SizedBox(height: 10),
                        _DetailGrid(
                          items: [
                            _DetailGridItem('Name', caseItem.studentName),
                            _DetailGridItem(
                              'Student Number',
                              caseItem.studentNumber,
                            ),
                            _DetailGridItem(
                              'Grade & Section',
                              caseItem.programGradeSection,
                            ),
                            _DetailGridItem(
                              'Previous Violations',
                              caseItem.priorViolationsCount == 0
                                  ? 'None'
                                  : '${caseItem.priorViolationsCount} offense'
                                      '${caseItem.priorViolationsCount == 1 ? '' : 's'}',
                              valueColor: caseItem.priorViolationsCount > 0
                                  ? _DashboardColors.priorViolationBadgeText
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const _DetailSectionHeader(
                          icon: Icons.description_outlined,
                          title: 'Incident Details',
                        ),
                        const SizedBox(height: 10),
                        _DetailGrid(
                          items: [
                            _DetailGridItem(
                              'Submitted By',
                              caseItem.submittedBy,
                            ),
                            _DetailGridItem(
                              'Location',
                              caseItem.incidentLocation,
                            ),
                            _DetailGridItem(
                              'Date & Time',
                              _formatFullDateTime(caseItem.incidentDateTime),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const _DetailSectionHeader(
                          icon: Icons.tag,
                          title: 'Description',
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _DashboardColors.surfaceBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _DashboardColors.cardBorder,
                            ),
                          ),
                          child: Text(
                            caseItem.description,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              height: 1.5,
                              color: _DashboardColors.primaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Validate',
                    icon: Icons.check,
                    color: _DashboardColors.validateGreen,
                    mutedColor: _DashboardColors.validateMuted,
                    onPressed: caseItem == null ? null : onValidate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Modify',
                    icon: Icons.edit_outlined,
                    color: _DashboardColors.modifyBlue,
                    mutedColor: _DashboardColors.modifyMuted,
                    onPressed: caseItem == null ? null : onModify,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Deny',
                    icon: Icons.close,
                    color: _DashboardColors.denyRed,
                    mutedColor: _DashboardColors.denyMuted,
                    onPressed: caseItem == null ? null : onDeny,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsEmptyState extends StatelessWidget {
  const _DetailsEmptyState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fact_check_outlined,
                    size: 48,
                    color: _DashboardColors.emptyStateIcon,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No case selected',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _DashboardColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a pending slip from the queue to review it',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlaDeadlineBadge extends StatelessWidget {
  const _SlaDeadlineBadge({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _DashboardColors.slaDeadlineBadgeBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time, size: 13, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            'SLA Deadline ${label ?? '--:--'}',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityWarningBanner extends StatelessWidget {
  const _SecurityWarningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _DashboardColors.warningBannerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _DashboardColors.warningBannerBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: _DashboardColors.warningBannerText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Security Escalation - Immediate Action Required',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _DashboardColors.warningBannerText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSectionHeader extends StatelessWidget {
  const _DetailSectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _DashboardColors.queueHeaderStart),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _DashboardColors.primaryText,
          ),
        ),
      ],
    );
  }
}

class _DetailGridItem {
  const _DetailGridItem(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.items});

  final List<_DetailGridItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 480 ? 1 : 2;
        return Wrap(
          spacing: 24,
          runSpacing: 14,
          children: items.map((item) {
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 24) / 2;
            return SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.value,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: item.valueColor ?? _DashboardColors.primaryText,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.mutedColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color mutedColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: mutedColor,
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Good Moral Management — Requests / Students List queue + Preview panel
// ---------------------------------------------------------------------------

/// Standalone Good Moral Management view: a left sidebar that switches
/// between the pending Requests queue and the full Students List directory,
/// and a right Preview panel that reviews whichever student is selected and
/// lets the officer generate + print a Good Moral certificate for them.
class GoodMoralManagementView extends StatelessWidget {
  const GoodMoralManagementView({
    super.key,
    required this.controller,
    required this.onGenerateCertificate,
  });

  final GoodMoralDashboardController controller;
  final VoidCallback onGenerateCertificate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final stackColumns = constraints.maxWidth < 900;

            final sidebar = _GoodMoralQueueSidebar(controller: controller);
            final preview = _GoodMoralPreviewPanel(
              controller: controller,
              onGenerateCertificate: onGenerateCertificate,
            );

            if (stackColumns) {
              return Column(
                children: [
                  Expanded(flex: 4, child: sidebar),
                  const SizedBox(height: 16),
                  Expanded(flex: 6, child: preview),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: sidebar),
                const SizedBox(width: 16),
                Expanded(flex: 7, child: preview),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Left panel — Requests queue / Students List directory
// ---------------------------------------------------------------------------

class _GoodMoralQueueSidebar extends StatefulWidget {
  const _GoodMoralQueueSidebar({required this.controller});

  final GoodMoralDashboardController controller;

  @override
  State<_GoodMoralQueueSidebar> createState() => _GoodMoralQueueSidebarState();
}

class _GoodMoralQueueSidebarState extends State<_GoodMoralQueueSidebar> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GoodMoralRequestModel> get _filteredRequests {
    final query = _searchQuery.trim().toLowerCase();
    final requests = widget.controller.requests;
    if (query.isEmpty) return requests;

    return requests.where((r) {
      return r.studentName.toLowerCase().contains(query) ||
          r.studentNumber.toLowerCase().contains(query) ||
          r.documentType.toLowerCase().contains(query);
    }).toList();
  }

  List<StudentDirectoryEntryModel> get _filteredStudents {
    final query = _searchQuery.trim().toLowerCase();
    final students = widget.controller.students;
    if (query.isEmpty) return students;

    return students.where((s) {
      return s.studentName.toLowerCase().contains(query) ||
          s.studentNumber.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isRequestsTab = controller.activeSubTab == GoodMoralSubTab.requests;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _DashboardColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _DashboardColors.cardBorder),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _DashboardTabButton(
                  label: 'Requests',
                  isActive: isRequestsTab,
                  onTap: () =>
                      controller.selectSubTab(GoodMoralSubTab.requests),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DashboardTabButton(
                  label: 'Students List',
                  isActive: !isRequestsTab,
                  onTap: () =>
                      controller.selectSubTab(GoodMoralSubTab.studentsList),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            isRequestsTab ? 'Requests Queue' : 'Students List',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _DashboardColors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isRequestsTab
                ? 'Total requests: ${controller.requests.length}'
                : 'Total students: ${controller.students.length}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _DashboardColors.secondaryText,
            ),
          ),
          const SizedBox(height: 14),
          _QueueSearchField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: isRequestsTab
                ? _buildRequestsList(controller)
                : _buildStudentsList(controller),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList(GoodMoralDashboardController controller) {
    final requests = _filteredRequests;
    if (requests.isEmpty) return const _GoodMoralQueueEmptyState();

    final selected = controller.selectedStudentRequest;
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: requests.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: _DashboardColors.cardBorder),
      itemBuilder: (context, index) {
        final request = requests[index];
        return _GoodMoralRequestTile(
          request: request,
          isSelected: selected?.sourceSubTab == GoodMoralSubTab.requests &&
              selected?.sourceId == request.id,
          onTap: () => controller.selectRequest(request),
        );
      },
    );
  }

  Widget _buildStudentsList(GoodMoralDashboardController controller) {
    final students = _filteredStudents;
    if (students.isEmpty) return const _StudentDirectoryEmptyState();

    final selected = controller.selectedStudentRequest;
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: students.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: _DashboardColors.cardBorder),
      itemBuilder: (context, index) {
        final student = students[index];
        return _StudentDirectoryTile(
          student: student,
          isSelected: selected?.sourceSubTab == GoodMoralSubTab.studentsList &&
              selected?.sourceId == student.id,
          onTap: () => controller.selectStudent(student),
        );
      },
    );
  }
}

class _GoodMoralQueueEmptyState extends StatelessWidget {
  const _GoodMoralQueueEmptyState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.assignment_outlined,
                    size: 48,
                    color: _DashboardColors.emptyStateIcon,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No pending requests',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GoodMoralRequestTile extends StatelessWidget {
  const _GoodMoralRequestTile({
    required this.request,
    required this.isSelected,
    required this.onTap,
  });

  final GoodMoralRequestModel request;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
          border: Border(
            left: BorderSide(
              width: 3,
              color: isSelected
                  ? _DashboardColors.queueHeaderStart
                  : Colors.transparent,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.studentName,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _DashboardColors.primaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${request.documentType}\n'
              '${request.programGradeSection} · ${_timeAgoLabel(request.requestDateTime)}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.4,
                color: _DashboardColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Requested by: ${request.requestedBy}',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: _DashboardColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentDirectoryTile extends StatelessWidget {
  const _StudentDirectoryTile({
    required this.student,
    required this.isSelected,
    required this.onTap,
  });

  final StudentDirectoryEntryModel student;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
          border: Border(
            left: BorderSide(
              width: 3,
              color: isSelected
                  ? _DashboardColors.queueHeaderStart
                  : Colors.transparent,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              student.studentName,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _DashboardColors.primaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${student.studentNumber} · ${student.programGradeSection}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: _DashboardColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              student.status,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _DashboardColors.queueHeaderStart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentDirectoryEmptyState extends StatelessWidget {
  const _StudentDirectoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.groups_outlined,
                    size: 48,
                    color: _DashboardColors.emptyStateIcon,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No students found',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Right panel — Preview / review + certificate generation
// ---------------------------------------------------------------------------

class _GoodMoralPreviewPanel extends StatelessWidget {
  const _GoodMoralPreviewPanel({
    required this.controller,
    required this.onGenerateCertificate,
  });

  final GoodMoralDashboardController controller;
  final VoidCallback onGenerateCertificate;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedStudentRequest;

    return Container(
      decoration: BoxDecoration(
        color: _DashboardColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _DashboardColors.cardBorder),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _DashboardColors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Review Good Moral',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: _DashboardColors.secondaryText,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: selected == null
                ? const _GoodMoralPreviewEmptyState()
                : SingleChildScrollView(
                    child: _GoodMoralPreviewDetails(selected: selected),
                  ),
          ),
          const SizedBox(height: 20),
          Center(
            child: _GenerateCertificateButton(
              enabled: !controller.isEmptyState,
              onPressed: onGenerateCertificate,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoodMoralPreviewDetails extends StatelessWidget {
  const _GoodMoralPreviewDetails({required this.selected});

  final GoodMoralSelectedStudent selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DetailSectionHeader(
          icon: Icons.person_outline,
          title: 'Student Information',
        ),
        const SizedBox(height: 10),
        _DetailGrid(
          items: [
            _DetailGridItem('Name', selected.studentName),
            _DetailGridItem('Student Number', selected.studentNumber),
            _DetailGridItem('Grade & Section', selected.programGradeSection),
          ],
        ),
        if (selected.documentType != null) ...[
          const SizedBox(height: 20),
          const _DetailSectionHeader(
            icon: Icons.description_outlined,
            title: 'Request Details',
          ),
          const SizedBox(height: 10),
          _DetailGrid(
            items: [
              _DetailGridItem('Document Type', selected.documentType!),
              if (selected.purpose != null)
                _DetailGridItem('Purpose', selected.purpose!),
              if (selected.requestedBy != null)
                _DetailGridItem('Requested By', selected.requestedBy!),
              if (selected.requestDateTime != null)
                _DetailGridItem(
                  'Date & Time',
                  _formatFullDateTime(selected.requestDateTime!),
                ),
            ],
          ),
        ],
        if (selected.remarks.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _DetailSectionHeader(icon: Icons.tag, title: 'Remarks'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _DashboardColors.surfaceBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _DashboardColors.cardBorder),
            ),
            child: Text(
              selected.remarks,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: _DashboardColors.primaryText,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GoodMoralPreviewEmptyState extends StatelessWidget {
  const _GoodMoralPreviewEmptyState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      size: 32,
                      color: _DashboardColors.emptyStateIcon,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No student selected',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _DashboardColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a request from the queue to review it',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GenerateCertificateButton extends StatelessWidget {
  const _GenerateCertificateButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.edit_outlined, size: 16),
      label: Text(
        'Generate & Print Certificate',
        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _DashboardColors.activeTabColor,
        disabledBackgroundColor: _DashboardColors.goodMoralButtonMuted,
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }
}

// Notifications dropdown moved to widgets/notifications_popover.dart —
// shared verbatim with every other module.
