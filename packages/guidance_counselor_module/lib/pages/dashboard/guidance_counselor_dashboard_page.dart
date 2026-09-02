import 'dart:math' as math;

// Reuses the Discipline Officer module's shared header-popover components
// directly rather than duplicating them — `show` keeps only those names in
// scope, since that module's own DashboardHeaderNavBar/DashboardTabController
// would otherwise collide with this file's identically-named tab bar.
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        EmailListView,
        EmailPopover,
        LogoutConfirmationDialog,
        NotificationItemModel,
        NotificationsListView,
        NotificationsPopover,
        ProfileScreen,
        showHeaderPopover;
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../batch_student_analysis/batch_student_analysis_view.dart';
import '../single_student_analysis/single_student_analysis_view.dart';

// ---------------------------------------------------------------------------
// Data models — Supabase-ready. fromJson()/toJson() map onto snake_case
// Postgres columns so rows can be streamed straight in once the ML
// prediction pipeline is wired up.
// ---------------------------------------------------------------------------

class GuidanceCounselorMetricsModel {
  const GuidanceCounselorMetricsModel({
    this.totalStudents = 0,
    this.atRiskTrainingDataCount = 0,
    this.dropoutRatePercent = 0.0,
  });

  final int totalStudents;
  final int atRiskTrainingDataCount;
  final double dropoutRatePercent;

  factory GuidanceCounselorMetricsModel.fromJson(Map<String, dynamic> json) {
    return GuidanceCounselorMetricsModel(
      totalStudents: json['total_students'] as int? ?? 0,
      atRiskTrainingDataCount: json['at_risk_training_data_count'] as int? ?? 0,
      dropoutRatePercent:
          (json['dropout_rate_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_students': totalStudents,
      'at_risk_training_data_count': atRiskTrainingDataCount,
      'dropout_rate_percent': dropoutRatePercent,
    };
  }
}

/// Counts behind the "Risk Distribution" donut chart.
class RiskDistributionModel {
  const RiskDistributionModel({
    this.noDecline = 0,
    this.severe = 0,
    this.moderate = 0,
    this.mild = 0,
  });

  final int noDecline;
  final int severe;
  final int moderate;
  final int mild;

  int get total => noDecline + severe + moderate + mild;

  factory RiskDistributionModel.fromJson(Map<String, dynamic> json) {
    return RiskDistributionModel(
      noDecline: json['no_decline'] as int? ?? 0,
      severe: json['severe'] as int? ?? 0,
      moderate: json['moderate'] as int? ?? 0,
      mild: json['mild'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'no_decline': noDecline,
      'severe': severe,
      'moderate': moderate,
      'mild': mild,
    };
  }
}

// ModelMetricModel moved to dashboard_layout's model_comparison_card.dart —
// shared with the Admin Dashboard's ML & Thresholds page, which renders the
// exact same ModelComparisonCard against the same /model-info data.

/// One student evaluation slip waiting for the counselor's review.
class StudentRiskQueueItemModel {
  const StudentRiskQueueItemModel({
    required this.id,
    required this.studentName,
    required this.courseSection,
    required this.studentId,
    required this.riskPercent,
  });

  final String id;
  final String studentName;
  final String courseSection;
  final String studentId;

  /// Model-predicted dropout risk, 0–100.
  final double riskPercent;

  factory StudentRiskQueueItemModel.fromJson(Map<String, dynamic> json) {
    return StudentRiskQueueItemModel(
      id: json['id'] as String,
      studentName: json['student_name'] as String,
      courseSection: json['course_section'] as String,
      studentId: json['student_id'] as String,
      riskPercent: (json['risk_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_name': studentName,
      'course_section': courseSection,
      'student_id': studentId,
      'risk_percent': riskPercent,
    };
  }
}

// ---------------------------------------------------------------------------
// Mock data — used whenever the host app doesn't supply live data yet, so
// this package stays independently runnable/demoable without a backend.
// ---------------------------------------------------------------------------

abstract final class GuidanceCounselorMockData {
  static GuidanceCounselorMetricsModel getSummaryMetrics() {
    return const GuidanceCounselorMetricsModel(
      totalStudents: 1240,
      atRiskTrainingDataCount: 186,
      dropoutRatePercent: 8.4,
    );
  }

  static RiskDistributionModel getRiskDistribution() {
    return const RiskDistributionModel(
      noDecline: 640,
      severe: 92,
      moderate: 168,
      mild: 340,
    );
  }

  static List<ModelMetricModel> getModelComparisons() {
    return const [
      ModelMetricModel(
        modelName: 'Logistic Regression',
        rocAuc: 0.97,
        prAuc: 0.34,
        recall: 0.41,
        f1: 0.47,
      ),
      ModelMetricModel(
        modelName: 'Random Forest',
        rocAuc: 0.74,
        prAuc: 0.93,
        recall: 0.52,
        f1: 0.62,
      ),
      ModelMetricModel(
        modelName: 'SVM',
        rocAuc: 0.68,
        prAuc: 0.86,
        recall: 0.28,
        f1: 0.79,
      ),
      ModelMetricModel(
        modelName: 'XG Boost',
        rocAuc: 0.79,
        prAuc: 0.48,
        recall: 0.94,
        f1: 0.71,
      ),
    ];
  }

  static List<StudentRiskQueueItemModel> getApprovalQueue() {
    return const [
      StudentRiskQueueItemModel(
        id: 'q-1',
        studentName: 'Juan Dela Cruz',
        courseSection: 'BSIT - 4B',
        studentId: '02000123456',
        riskPercent: 82,
      ),
      StudentRiskQueueItemModel(
        id: 'q-2',
        studentName: 'Maria Santos',
        courseSection: 'BSCS - 3A',
        studentId: '02000123457',
        riskPercent: 55,
      ),
      StudentRiskQueueItemModel(
        id: 'q-3',
        studentName: 'Pedro Reyes',
        courseSection: 'BSIT - 2C',
        studentId: '02000123458',
        riskPercent: 18,
      ),
      StudentRiskQueueItemModel(
        id: 'q-4',
        studentName: 'Ana Garcia',
        courseSection: 'BSBA - 1A',
        studentId: '02000123459',
        riskPercent: 4,
      ),
      StudentRiskQueueItemModel(
        id: 'q-5',
        studentName: 'Liza Ramos',
        courseSection: 'BSIT - 4B',
        studentId: '02000123460',
        riskPercent: 71,
      ),
      StudentRiskQueueItemModel(
        id: 'q-6',
        studentName: 'Mark Villanueva',
        courseSection: 'BSCS - 2B',
        studentId: '02000123461',
        riskPercent: 39,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Tab navigation state
// ---------------------------------------------------------------------------

enum GuidanceCounselorTab {
  overview,
  singleStudentAnalysis,
  batchStudentAnalysis,
  systemOverview,
}

/// "View all notifications"/"View all emails" swap the main content area
/// exactly like a normal sub-nav tab does — header and sub-nav bar stay put
/// — rather than opening a new page/route. Not one of [GuidanceCounselorTab]'s
/// own values since it isn't a real, always-visible tab; tapping any real
/// tab clears this back to null.
enum _MailboxView { notifications, email }

extension on GuidanceCounselorTab {
  String get label => switch (this) {
        GuidanceCounselorTab.overview => 'Overview',
        GuidanceCounselorTab.singleStudentAnalysis => 'Single Student Analysis',
        GuidanceCounselorTab.batchStudentAnalysis => 'Batch Student Analysis',
        GuidanceCounselorTab.systemOverview => 'System Overview',
      };

  IconData get icon => switch (this) {
        GuidanceCounselorTab.overview => Icons.dashboard_outlined,
        GuidanceCounselorTab.singleStudentAnalysis =>
          Icons.person_search_outlined,
        GuidanceCounselorTab.batchStudentAnalysis => Icons.groups_outlined,
        GuidanceCounselorTab.systemOverview => Icons.query_stats_outlined,
      };
}

/// Tracks which top-level dashboard view is active. A thin [ValueNotifier]
/// so [DashboardHeaderNavBar] and the page body can both react without
/// threading a raw enum + setState callback pair through the widget tree.
class GuidanceCounselorDashboardController
    extends ValueNotifier<GuidanceCounselorTab> {
  GuidanceCounselorDashboardController([
    super.initialTab = GuidanceCounselorTab.overview,
  ]);

  void selectOverview() => value = GuidanceCounselorTab.overview;

  void selectSingleStudentAnalysis() =>
      value = GuidanceCounselorTab.singleStudentAnalysis;

  void selectBatchStudentAnalysis() =>
      value = GuidanceCounselorTab.batchStudentAnalysis;

  void selectSystemOverview() => value = GuidanceCounselorTab.systemOverview;
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _DashboardColors {
  // Header nav bar is always navy and never responds to theme — see
  // AppHeaderNavBar usage in the page build() below.
  static const headerBackground = Color(0xFF15253F);
  // Counselor name text sits on the navy header, so it must stay constant
  // regardless of theme too.
  static const gray = Color(0xFFE6E6E6);

  static Color surfaceBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF1F5F9);
  static Color card(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : const Color(0xFFFFFFFF);
  static Color cardBorder(BuildContext context) => context.isDarkMode
      ? const Color(0x0D334155) // rgba(51,65,85,0.05)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  static Color primaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
  static Color secondaryText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  static Color mutedIcon(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
  static Color emptyStateIcon(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF475569) : const Color(0xFFCBD5E1);

  static Color navBarBackground(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF16191D) : const Color(0xFFFFFFFF);
  static Color navBarBorder(BuildContext context) => context.isDarkMode
      ? const Color(0x0D334155) // rgba(51,65,85,0.05)
      : const Color(0x0D000000); // rgba(0,0,0,0.05)
  // Brand accent — stays constant across themes.
  static const navBarActiveText = Color(0xFF345892);
  static Color navBarInactiveText(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF8F8F8F);
  // Brand accent — stays constant across themes.
  static const navBarIndicator = Color(0xFF345892);

  // Brand accent — stays constant across themes.
  static const primaryAction = Color(0xFF345892);

  static Color searchFill(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF111111) : const Color(0xFFF1F5F9);
  static Color gridLine(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  // Shared 4-stop blue ramp for both the donut and the grouped bar chart —
  // "No decline"/"roc_auc" darkest through "Mild"/"f1" lightest. Brand/chart
  // accent colors — stay constant across themes.
  static const chartTone1 = Color(0xFF0F172A);
  static const chartTone2 = Color(0xFF2563EB);
  static const chartTone3 = Color(0xFF06B6D4);
  static const chartTone4 = Color(0xFFA5F3FC);
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Guidance Counselor dashboard: dropout-risk analytics overview plus an
/// approval queue for pending student evaluation slips.
///
/// Standalone and Supabase-ready — pass `initialX` to seed it with live
/// data; omitted values fall back to [GuidanceCounselorMockData] so this
/// widget stays demoable without a backend.
class GuidanceCounselorDashboard extends StatefulWidget {
  const GuidanceCounselorDashboard({
    super.key,
    this.counselorName = 'Juan Dela Cruz',
    this.onReturnToHub,
    this.onSignOut,
    this.initialMetrics,
    this.initialRiskDistribution,
    this.initialModelComparisons,
    this.initialApprovalQueue,
    this.onDownloadSnapshot,
    this.onApproveSlip,
    this.onAnalyzeSingle,
    this.onDownloadSingleAssessment,
    this.onAnalyzeBatch,
    this.onDownloadBatchResults,
    this.initialNotifications,
    this.onMarkNotificationsRead,
    required this.systemOverviewTabBuilder,
  });

  final String counselorName;

  /// Set when Admin opens this page from the hub as a preview; renders a
  /// back button in the header. Null for a Guidance Counselor's own direct
  /// login route, where there is no hub to return to.
  final VoidCallback? onReturnToHub;

  /// Renders a logout action in the profile menu when set.
  final VoidCallback? onSignOut;

  final GuidanceCounselorMetricsModel? initialMetrics;
  final RiskDistributionModel? initialRiskDistribution;
  final List<ModelMetricModel>? initialModelComparisons;
  final List<StudentRiskQueueItemModel>? initialApprovalQueue;

  /// Notifications targeted at this dashboard from the centralized
  /// notification system (Admin's Notifications page). Falls back to an
  /// empty bell when omitted (demo behavior).
  final List<NotificationItemModel>? initialNotifications;

  /// Marks every currently-unread notification read — invoked by the bell's
  /// "View all notifications" action.
  final Future<void> Function()? onMarkNotificationsRead;

  /// Persists/exports the current analytics snapshot. When omitted, the
  /// button just surfaces a confirmation snackbar (demo behavior).
  final Future<void> Function()? onDownloadSnapshot;

  /// Called when a queue slip is approved (tapped), by slip id. When
  /// omitted, only local state is mutated (demo behavior).
  final Future<void> Function(String slipId)? onApproveSlip;

  /// Scores a single student's [StudentRiskInputModel] against the real ML
  /// pipeline. Forwarded to [SingleStudentAnalysisView.onAnalyze]; omit to
  /// use that view's built-in demo calculator.
  final Future<RiskAnalysisResultModel> Function(StudentRiskInputModel input)?
      onAnalyzeSingle;

  /// Forwarded to [SingleStudentAnalysisView.onDownloadAssessment].
  final Future<void> Function(
    StudentRiskInputModel input,
    RiskAnalysisResultModel result,
  )? onDownloadSingleAssessment;

  /// Scores an uploaded roster against the real ML pipeline. Forwarded to
  /// [BatchStudentAnalysisView.onAnalyzeAll]; omit to use that view's
  /// built-in demo calculator.
  final Future<List<BatchAnalysisResultModel>> Function(
    List<BatchStudentRecordModel> records,
  )? onAnalyzeBatch;

  /// Forwarded to [BatchStudentAnalysisView.onDownloadResults].
  final Future<void> Function(
    List<BatchStudentRecordModel> records,
    List<BatchAnalysisResultModel> results,
  )? onDownloadBatchResults;

  /// Builds the System Overview tab's content — the exact same
  /// live-statistics view shown in the Admin module (System Overview page),
  /// reused verbatim here rather than reimplemented. The host app supplies
  /// this since it needs the app-level Supabase wiring
  /// (`SystemOverviewConnectedPage`) that this presentation-only package
  /// can't reach into directly.
  final WidgetBuilder systemOverviewTabBuilder;

  @override
  State<GuidanceCounselorDashboard> createState() =>
      _GuidanceCounselorDashboardState();
}

class _GuidanceCounselorDashboardState
    extends State<GuidanceCounselorDashboard> {
  final _tabController = GuidanceCounselorDashboardController();

  /// Non-null while "View all notifications"/"View all emails" is showing
  /// in place of the normal tab content. See [_MailboxView].
  _MailboxView? _mailboxView;

  // Drives the page's Theme; always light now that the header's Settings
  // entry point (and its Dark Mode toggle) has been removed.
  final _themeMode = ValueNotifier(ThemeMode.light);

  late List<NotificationItemModel> _notifications;

  late GuidanceCounselorMetricsModel _metrics;
  late RiskDistributionModel _riskDistribution;
  late List<ModelMetricModel> _modelComparisons;
  late List<StudentRiskQueueItemModel> _approvalQueue;

  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _metrics =
        widget.initialMetrics ?? GuidanceCounselorMockData.getSummaryMetrics();
    _riskDistribution = widget.initialRiskDistribution ??
        GuidanceCounselorMockData.getRiskDistribution();
    _modelComparisons = widget.initialModelComparisons ??
        GuidanceCounselorMockData.getModelComparisons();
    _approvalQueue = List.of(
      widget.initialApprovalQueue ??
          GuidanceCounselorMockData.getApprovalQueue(),
    );
    _notifications = List.of(widget.initialNotifications ?? const []);
  }

  /// The host app's connected page reloads notifications (e.g. after a
  /// realtime insert from Admin's Notifications page) by rebuilding this
  /// widget with a fresh `initialNotifications` list — `initState` above
  /// only seeds it once, so without this the bell would never actually
  /// update live.
  @override
  void didUpdateWidget(covariant GuidanceCounselorDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fresh = widget.initialNotifications;
    if (fresh != null && !identical(fresh, oldWidget.initialNotifications)) {
      setState(() => _notifications = List.of(fresh));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleDownloadSnapshot() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      if (widget.onDownloadSnapshot != null) {
        await widget.onDownloadSnapshot!.call();
      }
      _showSnackBar('Data snapshot downloaded.');
    } catch (e) {
      _showSnackBar('Could not download snapshot: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _handleApproveSlip(StudentRiskQueueItemModel slip) async {
    try {
      await widget.onApproveSlip?.call(slip.id);
      if (!mounted) return;
      setState(() => _approvalQueue.removeWhere((s) => s.id == slip.id));
      _showSnackBar('${slip.studentName} moved out of the queue.');
    } catch (e) {
      _showSnackBar('Could not update this slip: $e');
    }
  }

  // Every popover below opens through the shared showHeaderPopover() from
  // discipline_officer_module — same fixed top-right anchor, same
  // HeaderPopoverCard/PopoverHeaderBar chrome — so Notifications and Account
  // render pixel-identical to the Discipline Officer header.

  /// `ProfileScreen` is pushed onto the app's root `Navigator`, so its
  /// subtree lands outside this page's own local `Theme` (the same
  /// Overlay-escapes-local-Theme issue as the header popovers) — wrap it in
  /// a `Theme` matching the current toggle so its `context.isDarkMode`
  /// reads correctly instead of always seeing the app's ambient theme.
  Widget _themedProfileScreen() {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _DashboardColors.headerBackground,
        brightness: _themeMode.value == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light,
      ),
      child: const ProfileScreen(),
    );
  }

  void _openProfile() {
    showHeaderPopover(
      context: context,
      cardWidth: 260,
      // Anchor near the Profile icon just above the bottom nav bar on
      // mobile, rather than centering — it stays visually tethered to
      // what opened it.
      anchorAboveBottomNav: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return AccountProfileMenu(
          onViewProfile: () {
            Navigator.of(popoverContext).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => _themedProfileScreen()));
          },
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onToggleDarkMode: () {
            _themeMode.value = _themeMode.value == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
            setPopoverState(() {});
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
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onConfirm: () {
            Navigator.of(dialogContext).pop();
            widget.onSignOut?.call();
          },
        );
      },
    );
  }

  Future<void> _markNotificationsRead() async {
    if (_notifications.every((n) => n.isRead)) return;
    setState(() {
      _notifications =
          _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });
    try {
      await widget.onMarkNotificationsRead?.call();
    } catch (e) {
      debugPrint('Could not mark notifications read: $e');
    }
  }

  void _showNotificationsMenu() {
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: _notifications,
          accentColor: _DashboardColors.primaryAction,
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onViewAll: () {
            Navigator.of(popoverContext).pop();
            setState(() => _mailboxView = _MailboxView.notifications);
          },
          onMarkAllRead: () {
            Navigator.of(popoverContext).pop();
            _markNotificationsRead();
          },
        );
      },
    );
  }

  void _showEmailMenu() {
    showHeaderPopover(
      context: context,
      cardWidth: 400,
      centered: context.isMobileWidth,
      contentBuilder: (popoverContext, setPopoverState) {
        return EmailPopover(
          emails: const [], // no email backend yet — see EmailPopover doc comment
          isDarkMode: _themeMode.value == ThemeMode.dark,
          onViewAll: () {
            Navigator.of(popoverContext).pop();
            setState(() => _mailboxView = _MailboxView.email);
          },
          onMarkAllRead: () =>
              Navigator.of(popoverContext).pop(), // nothing to mark yet
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: _DashboardColors.headerBackground,
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ),
          // A nested Builder so `context` below is a genuine descendant of
          // this Theme (and thus of `context.isDarkMode`) rather than the
          // ambient context from above it — the Scaffold and its body are
          // rebuilt fresh on every theme toggle instead of being cached via
          // ValueListenableBuilder's `child` optimization, precisely so
          // Theme-dependent colors below actually respond to the toggle.
          child: Builder(
            builder: (context) {
              final isMobile = context.isMobileWidth;

              final header = AppHeaderNavBar(
                title: 'Guidance Counselor Dashboard',
                subtitle: 'Mission Control',
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onReturnToHub != null) ...[
                      HeaderIconButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: widget.onReturnToHub!,
                      ),
                      const SizedBox(width: 12),
                    ],
                    const SchoolLogo(),
                  ],
                ),
                actions: [
                  if (!isMobile) ...[
                    HeaderIconButton(
                      icon: Icons.mail_outline_rounded,
                      onTap: _showEmailMenu,
                    ),
                    HeaderIconButton(
                      icon: Icons.notifications_outlined,
                      badgeCount: unreadCount,
                      onTap: _showNotificationsMenu,
                    ),
                    const SizedBox(width: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => _themedProfileScreen()),
                          ),
                          child: Text(
                            widget.counselorName,
                            style: GoogleFonts.poppins(
                              fontSize: context.isMobileWidth ? 14 : 16,
                              fontWeight: FontWeight.w600,
                              color: _DashboardColors.gray,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        ProfileAvatarButton(onTap: _openProfile),
                      ],
                    ),
                  ],
                ],
              );

              // Tab bar + main content share the same 1440px-capped,
              // centered frame every dashboard module uses (see
              // DashboardPageWrapper).
              final pageContent = DashboardPageWrapper(
                // On mobile the cards should use nearly the full screen
                // width instead of losing 48px total to the desktop's
                // 24px side margins.
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 5 : 24,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<GuidanceCounselorTab>(
                      valueListenable: _tabController,
                      builder: (context, activeTab, _) {
                        return DashboardHeaderNavBar(
                          activeTab: activeTab,
                          onTabSelected: (tab) {
                            setState(() => _mailboxView = null);
                            _tabController.value = tab;
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Every tab sizes to its own content instead of being
                    // squeezed into a fixed Expanded share of the viewport
                    // with its own internal scroll — the whole page
                    // (including the header, see body below) scrolls
                    // instead, so nothing has to shrink past its natural
                    // size or scroll twice.
                    ValueListenableBuilder<GuidanceCounselorTab>(
                      valueListenable: _tabController,
                      builder: (context, activeTab, _) {
                        return _buildBody(activeTab, isMobile: isMobile);
                      },
                    ),
                  ],
                ),
              );

              return Scaffold(
                backgroundColor: _DashboardColors.surfaceBackground(context),
                bottomNavigationBar: isMobile
                    ? AppBottomNavBar(
                        onEmailTap: _showEmailMenu,
                        onNotificationTap: _showNotificationsMenu,
                        onProfileTap: _openProfile,
                        notificationBadgeCount: unreadCount,
                        isDarkMode: _themeMode.value == ThemeMode.dark,
                      )
                    : null,
                // The whole body is one scrollable column so a short
                // viewport never clips tab content with no way to reach the
                // rest of it.
                body: SingleChildScrollView(
                  child: Column(children: [header, pageContent]),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBody(GuidanceCounselorTab activeTab, {required bool isMobile}) {
    switch (_mailboxView) {
      case _MailboxView.notifications:
        return NotificationsListView(
          notifications: _notifications,
          isDarkMode: _themeMode.value == ThemeMode.dark,
        );
      case _MailboxView.email:
        return EmailListView(isDarkMode: _themeMode.value == ThemeMode.dark);
      case null:
        return _buildTabContent(activeTab, isMobile: isMobile);
    }
  }

  Widget _buildTabContent(GuidanceCounselorTab activeTab,
      {required bool isMobile}) {
    return switch (activeTab) {
      GuidanceCounselorTab.overview => _OverviewTab(
          metrics: _metrics,
          riskDistribution: _riskDistribution,
          modelComparisons: _modelComparisons,
          approvalQueue: _approvalQueue,
          downloading: _downloading,
          onDownloadSnapshot: _handleDownloadSnapshot,
          onApproveSlip: _handleApproveSlip,
          isMobile: isMobile,
        ),
      GuidanceCounselorTab.singleStudentAnalysis => SingleStudentAnalysisView(
          onAnalyze: widget.onAnalyzeSingle,
          onDownloadAssessment: widget.onDownloadSingleAssessment,
          isMobile: isMobile,
        ),
      GuidanceCounselorTab.batchStudentAnalysis => BatchStudentAnalysisView(
          onAnalyzeAll: widget.onAnalyzeBatch,
          onDownloadResults: widget.onDownloadBatchResults,
        ),
      GuidanceCounselorTab.systemOverview =>
        widget.systemOverviewTabBuilder(context),
    };
  }
}

// Account/Logout/Notifications popovers are the shared
// discipline_officer_module widgets (AccountProfileMenu,
// LogoutConfirmationDialog, NotificationsPopover) reused verbatim below —
// see _openProfile / _showNotificationsMenu.

// ---------------------------------------------------------------------------
// Secondary tab bar (Overview / Single Student Analysis / Batch Student
// Analysis) — flat underline-tab style flush against the header's bottom
// edge.
// ---------------------------------------------------------------------------

class DashboardHeaderNavBar extends StatelessWidget {
  const DashboardHeaderNavBar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  final GuidanceCounselorTab activeTab;
  final ValueChanged<GuidanceCounselorTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _DashboardColors.navBarBackground(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _DashboardColors.navBarBorder(context)),
      ),
      // Horizontally scrollable — at mobile widths the tab labels plus
      // spacing don't fit the viewport, and this bar has no business
      // shrinking or wrapping them (matches Figma's own `overflow-x-auto`
      // on this bar). The Container's own fixed height:48 still bounds the
      // Row's cross axis, so nothing overflows vertically either.
      // ScrollConfiguration: Flutter's default ScrollBehavior excludes
      // mouse from dragDevices, which would otherwise leave the overflowing
      // tabs unreachable for a desktop mouse user (touch/trackpad drag
      // still worked; a plain click-drag or scroll didn't).
      child: ScrollConfiguration(
        behavior: mouseDraggableScrollBehavior,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            // Stretch so each item's indicator (Positioned bottom: 0) lands
            // flush on the bar's own bottom edge rather than being inset by
            // the row's vertical centering.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tab in GuidanceCounselorTab.values) ...[
                _NavBarItem(
                  label: tab.label,
                  icon: tab.icon,
                  isActive: activeTab == tab,
                  onTap: () => onTabSelected(tab),
                ),
                if (tab != GuidanceCounselorTab.values.last)
                  const SizedBox(width: 45),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? _DashboardColors.navBarActiveText
        : _DashboardColors.navBarInactiveText(context);
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 11 : 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: isActive
                    ? _DashboardColors.navBarIndicator
                    : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview tab — two-column layout
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.metrics,
    required this.riskDistribution,
    required this.modelComparisons,
    required this.approvalQueue,
    required this.downloading,
    required this.onDownloadSnapshot,
    required this.onApproveSlip,
    required this.isMobile,
  });

  final GuidanceCounselorMetricsModel metrics;
  final RiskDistributionModel riskDistribution;
  final List<ModelMetricModel> modelComparisons;
  final List<StudentRiskQueueItemModel> approvalQueue;
  final bool downloading;
  final VoidCallback onDownloadSnapshot;
  final ValueChanged<StudentRiskQueueItemModel> onApproveSlip;

  /// True when the page has no bounded height to hand this tab (it
  /// scrolls instead) — sizes to its own content rather than wrapping
  /// itself in another `SingleChildScrollView`, which would be nested
  /// inside the page's own and need bounded height it won't have.
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final analytics = _AnalyticsColumn(
      metrics: metrics,
      riskDistribution: riskDistribution,
      modelComparisons: modelComparisons,
      downloading: downloading,
      onDownloadSnapshot: onDownloadSnapshot,
    );

    final queue = _ApprovalQueueCard(
      items: approvalQueue,
      onApprove: onApproveSlip,
    );

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          analytics,
          const SizedBox(height: 20),
          queue,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 1000;

        if (stackColumns) {
          return Column(
            children: [
              analytics,
              const SizedBox(height: 20),
              queue,
            ],
          );
        }

        // Master-detail: the approval-queue "sidebar" is height-locked to
        // match the analytics column (CrossAxisAlignment.stretch), capped
        // so the pair never grows past ~one viewport — the queue's own
        // list, and the analytics column, scroll internally within that
        // fixed height instead.
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: context.masterDetailRowMaxHeight()),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: analytics),
              const SizedBox(width: 18),
              SizedBox(width: 320, child: queue),
            ],
          ),
        );
      },
    );
  }
}

class _AnalyticsColumn extends StatelessWidget {
  const _AnalyticsColumn({
    required this.metrics,
    required this.riskDistribution,
    required this.modelComparisons,
    required this.downloading,
    required this.onDownloadSnapshot,
  });

  final GuidanceCounselorMetricsModel metrics;
  final RiskDistributionModel riskDistribution;
  final List<ModelMetricModel> modelComparisons;
  final bool downloading;
  final VoidCallback onDownloadSnapshot;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MetricsRow(metrics: metrics),
        const SizedBox(height: 20),
        _RiskDistributionCard(
          distribution: riskDistribution,
          downloading: downloading,
          onDownloadSnapshot: onDownloadSnapshot,
        ),
        const SizedBox(height: 20),
        ModelComparisonCard(models: modelComparisons),
      ],
    );

    // When an ancestor gives this column a bounded height to match its
    // queue sibling (the desktop master-detail Row), scroll internally
    // within whatever's left instead of overflowing; otherwise (mobile/
    // stacked) just size to content, as the page scrolls at the outer
    // level.
    return LayoutBuilder(
      builder: (context, constraints) {
        return constraints.hasBoundedHeight
            ? SingleChildScrollView(child: content)
            : content;
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Stat row
// ---------------------------------------------------------------------------

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.metrics});

  final GuidanceCounselorMetricsModel metrics;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MetricCard(
        label: 'Total Students',
        value: '${metrics.totalStudents}',
        icon: Icons.people_outline_rounded,
      ),
      _MetricCard(
        label: 'At-Risk Training Data',
        value: '${metrics.atRiskTrainingDataCount}',
        icon: Icons.warning_amber_rounded,
      ),
      _MetricCard(
        label: 'Dropout Rate',
        value: '${metrics.dropoutRatePercent.toStringAsFixed(1)}%',
        icon: Icons.show_chart_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;

        if (isNarrow) {
          return MobileMetricGrid(cards: cards, spacing: 16);
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                Expanded(child: card),
                if (card != cards.last) const SizedBox(width: 16),
              ],
            ],
          ),
        );
      },
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
      padding: const EdgeInsets.fromLTRB(27, 16, 20, 16),
      decoration: BoxDecoration(
        color: _DashboardColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _DashboardColors.cardBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.isMobileWidth ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: _DashboardColors.secondaryText(context),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 30 : 32,
                      fontWeight: FontWeight.w600,
                      color: _DashboardColors.primaryText(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 24, color: _DashboardColors.secondaryText(context)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Risk Distribution card (donut chart)
// ---------------------------------------------------------------------------

class _RiskDistributionCard extends StatelessWidget {
  const _RiskDistributionCard({
    required this.distribution,
    required this.downloading,
    required this.onDownloadSnapshot,
  });

  final RiskDistributionModel distribution;
  final bool downloading;
  final VoidCallback onDownloadSnapshot;

  static const _slices = [
    ('No decline', _DashboardColors.chartTone1),
    ('Severe', _DashboardColors.chartTone2),
    ('Moderate', _DashboardColors.chartTone3),
    ('Mild', _DashboardColors.chartTone4),
  ];

  @override
  Widget build(BuildContext context) {
    final values = [
      distribution.noDecline,
      distribution.severe,
      distribution.moderate,
      distribution.mild,
    ];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Risk Distribution',
            style: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 16 : 18,
              fontWeight: FontWeight.w700,
              color: _DashboardColors.primaryText(context),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 420;
              final donut = _DonutChart(
                segments: [
                  for (var i = 0; i < _slices.length; i++)
                    _ChartSegment(
                        value: values[i].toDouble(), color: _slices[i].$2),
                ],
                emptyTrackColor: _DashboardColors.gridLine(context),
              );
              final legend = _ChartLegend(
                entries: [for (final s in _slices) (s.$1, s.$2)],
              );

              if (stack) {
                return Column(
                  children: [
                    donut,
                    const SizedBox(height: 20),
                    legend,
                  ],
                );
              }

              return Row(
                children: [
                  donut,
                  const SizedBox(width: 32),
                  legend,
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: _PrimaryActionButton(
              label: 'Download Data Snapshot',
              icon: Icons.download_rounded,
              loading: downloading,
              onPressed: onDownloadSnapshot,
            ),
          ),
        ],
      ),
    );
  }
}

// ModelComparisonCard (the "Trained Model Comparison" grouped bar chart)
// moved to dashboard_layout's model_comparison_card.dart — see its usage in
// _AnalyticsColumn above.

/// Shared white/rounded/bordered wrapper for the two chart cards.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _DashboardColors.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _DashboardColors.cardBorder(context)),
      ),
      child: child,
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _DashboardColors.primaryAction,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          else
            Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Colored dot + label, stacked vertically — shared by both chart cards.
class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.entries});

  final List<(String, Color)> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: entry.$2, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                entry.$1,
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w500,
                  color: _DashboardColors.primaryText(context),
                ),
              ),
            ],
          ),
          if (entry != entries.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Donut chart
// ---------------------------------------------------------------------------

class _ChartSegment {
  const _ChartSegment({required this.value, required this.color});

  final double value;
  final Color color;
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.segments, required this.emptyTrackColor});

  final List<_ChartSegment> segments;

  /// Track color drawn when every segment is 0 — a "surface family" color
  /// (sits on the card behind it), so it's passed in from the widget layer
  /// rather than read directly by this custom painter.
  final Color emptyTrackColor;

  static const _size = 180.0;
  static const _strokeWidth = 30.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: CustomPaint(
        painter: _DonutChartPainter(
          segments: segments,
          strokeWidth: _strokeWidth,
          emptyTrackColor: emptyTrackColor,
        ),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({
    required this.segments,
    required this.strokeWidth,
    required this.emptyTrackColor,
  });

  final List<_ChartSegment> segments;
  final double strokeWidth;
  final Color emptyTrackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (total <= 0) {
      final paint = Paint()
        ..color = emptyTrackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, 0, 2 * math.pi, false, paint);
      return;
    }

    var startAngle = -math.pi / 2;
    const gapRadians = 0.02;
    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweep = (segment.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        rect,
        startAngle,
        math.max(sweep - gapRadians, 0.001),
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.emptyTrackColor != emptyTrackColor;
  }
}

// Grouped bar chart (_GroupedBarChart/_GroupedBarChartRow/_BarGroup/_Bar)
// moved to dashboard_layout's model_comparison_card.dart along with
// _ModelComparisonCard above.

// ---------------------------------------------------------------------------
// At-Risk Students sidebar — structured to match `professor_module`'s
// `_SectionListCard` / `discipline_officer_module`'s `ValidationQueueCard`
// exactly (same header layout, search+filter row, row treatment) so every
// dashboard in this system reads as one consistent design system.
// ---------------------------------------------------------------------------

class _ApprovalQueueCard extends StatefulWidget {
  const _ApprovalQueueCard({required this.items, required this.onApprove});

  final List<StudentRiskQueueItemModel> items;
  final ValueChanged<StudentRiskQueueItemModel> onApprove;

  @override
  State<_ApprovalQueueCard> createState() => _ApprovalQueueCardState();
}

class _ApprovalQueueCardState extends State<_ApprovalQueueCard> {
  int get _pageSize => context.isMobileWidth ? 10 : 20;

  final _searchController = TextEditingController();
  String _query = '';
  int _currentPage = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StudentRiskQueueItemModel> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    return widget.items.where((item) {
      return item.studentName.toLowerCase().contains(query) ||
          item.courseSection.toLowerCase().contains(query) ||
          item.studentId.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final totalPages =
        filtered.isEmpty ? 1 : (filtered.length / _pageSize).ceil();
    final currentPage = _currentPage.clamp(1, totalPages);
    final pageItems =
        filtered.skip((currentPage - 1) * _pageSize).take(_pageSize).toList();

    // Header/search stay fixed; only the list scrolls — as a bounded,
    // real-scrolling Expanded when an ancestor gives this card a fixed
    // height to match its analytics-column sibling (the desktop
    // master-detail Row), or as a Flexible that hugs up to whatever's
    // available when it doesn't (mobile/stacked, where the page itself
    // scrolls instead).
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        final Widget list = filtered.isEmpty
            ? const _QueueEmptyState()
            : ListView.builder(
                shrinkWrap: !bounded,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
                itemCount: pageItems.length,
                itemBuilder: (context, index) {
                  final item = pageItems[index];
                  return _QueueItemTile(
                    item: item,
                    onTap: () => widget.onApprove(item),
                  );
                },
              );

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _DashboardColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _DashboardColors.cardBorder(context)),
          ),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(29, 24, 29, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'At-Risk Students',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: _DashboardColors.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total students: ${widget.items.length}',
                      style: GoogleFonts.poppins(
                        fontSize: context.isMobileWidth ? 11 : 13,
                        fontWeight: FontWeight.w400,
                        color: _DashboardColors.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 19, 25, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _QueueSearchField(
                        controller: _searchController,
                        onChanged: (value) => setState(() {
                          _query = value;
                          _currentPage = 1;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _QueueFilterButton(onTap: () {}),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              bounded ? Expanded(child: list) : Flexible(child: list),
              if (filtered.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                  child: CardPaginationFooter(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    totalCount: filtered.length,
                    textColor: _DashboardColors.secondaryText(context),
                    accentColor: _DashboardColors.primaryAction,
                    mutedBackground: _DashboardColors.surfaceBackground(context),
                    onPrevious: () =>
                        setState(() => _currentPage = currentPage - 1),
                    onNext: () =>
                        setState(() => _currentPage = currentPage + 1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QueueSearchField extends StatelessWidget {
  const _QueueSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.poppins(
            fontSize: context.isMobileWidth ? 11 : 13,
            color: _DashboardColors.primaryText(context)),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search',
          hintStyle: GoogleFonts.poppins(
              fontSize: context.isMobileWidth ? 11 : 13,
              color: _DashboardColors.mutedIcon(context)),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: _DashboardColors.mutedIcon(context)),
          filled: true,
          fillColor: _DashboardColors.searchFill(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _QueueFilterButton extends StatelessWidget {
  const _QueueFilterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _DashboardColors.searchFill(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 32,
          width: 107,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: _DashboardColors.mutedIcon(context),
              ),
              const SizedBox(width: 6),
              Text(
                'Filter',
                style: GoogleFonts.poppins(
                  fontSize: context.isMobileWidth ? 11 : 13,
                  fontWeight: FontWeight.w400,
                  color: _DashboardColors.mutedIcon(context),
                ),
              ),
            ],
          ),
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
                  Icon(
                    Icons.task_alt_rounded,
                    size: 40,
                    color: _DashboardColors.emptyStateIcon(context),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No at-risk students found',
                    style: GoogleFonts.poppins(
                      fontSize: context.isMobileWidth ? 11 : 13,
                      fontWeight: FontWeight.w500,
                      color: _DashboardColors.secondaryText(context),
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

class _QueueItemTile extends StatelessWidget {
  const _QueueItemTile({required this.item, required this.onTap});

  final StudentRiskQueueItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 29, vertical: 18),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: _DashboardColors.cardBorder(context))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.studentName,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 12 : 14,
                fontWeight: FontWeight.w600,
                color: _DashboardColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.courseSection,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 10 : 12,
                fontWeight: FontWeight.w400,
                color: _DashboardColors.secondaryText(context),
              ),
            ),
            Text(
              item.studentId,
              style: GoogleFonts.poppins(
                fontSize: context.isMobileWidth ? 10 : 12,
                fontWeight: FontWeight.w400,
                color: _DashboardColors.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
