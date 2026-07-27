import 'dart:math' as math;

// Reuses the Discipline Officer module's shared header-popover components
// directly rather than duplicating them — `show` keeps only those names in
// scope, since that module's own DashboardHeaderNavBar/DashboardTabController
// would otherwise collide with this file's identically-named tab bar.
import 'package:discipline_officer_module/discipline_officer_module.dart'
    show
        AccountProfileMenu,
        LogoutConfirmationDialog,
        NotificationItemModel,
        NotificationsPopover,
        ProfileScreen,
        SettingsPopover,
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

/// One trained model's evaluation scores (all 0.0–1.0) behind a group of
/// bars in the "Trained Model Comparison" chart.
class ModelMetricModel {
  const ModelMetricModel({
    required this.modelName,
    required this.rocAuc,
    required this.prAuc,
    required this.recall,
    required this.f1,
  });

  final String modelName;
  final double rocAuc;
  final double prAuc;
  final double recall;
  final double f1;

  factory ModelMetricModel.fromJson(Map<String, dynamic> json) {
    return ModelMetricModel(
      modelName: json['model_name'] as String,
      rocAuc: (json['roc_auc'] as num?)?.toDouble() ?? 0.0,
      prAuc: (json['pr_auc'] as num?)?.toDouble() ?? 0.0,
      recall: (json['recall'] as num?)?.toDouble() ?? 0.0,
      f1: (json['f1'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model_name': modelName,
      'roc_auc': rocAuc,
      'pr_auc': prAuc,
      'recall': recall,
      'f1': f1,
    };
  }
}

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
}

extension on GuidanceCounselorTab {
  String get label => switch (this) {
        GuidanceCounselorTab.overview => 'Overview',
        GuidanceCounselorTab.singleStudentAnalysis => 'Single Student Analysis',
        GuidanceCounselorTab.batchStudentAnalysis => 'Batch Student Analysis',
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
}

// ---------------------------------------------------------------------------
// Theme tokens
// ---------------------------------------------------------------------------

abstract final class _DashboardColors {
  static const headerBackground = Color(0xFF15253F);
  static const headerBorder = Color(0x1AFFFFFF);
  static const headerChrome = Color(0x14FFFFFF);

  static const surfaceBackground = Color(0xFFF1F5F9);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE2E8F0);
  static const primaryText = Color(0xFF1E293B);
  static const secondaryText = Color(0xFF64748B);
  static const mutedIcon = Color(0xFF94A3B8);
  static const emptyStateIcon = Color(0xFFCBD5E1);

  static const navBarBackground = Color(0xFFFFFFFF);
  static const navBarBorder = Color(0xFFE2E8F0);
  static const navBarActiveText = Color(0xFF345892);
  static const navBarInactiveText = Color(0xFF8F8F8F);
  static const navBarIndicator = Color(0xFF345892);

  static const primaryAction = Color(0xFF345892);

  static const searchFill = Color(0xFFF1F5F9);
  static const queueItemBackground = Color(0xFFF8FAFC);
  static const gridLine = Color(0xFFE2E8F0);

  // Shared 4-stop blue ramp for both the donut and the grouped bar chart —
  // "No decline"/"roc_auc" darkest through "Mild"/"f1" lightest.
  static const chartTone1 = Color(0xFF0F172A);
  static const chartTone2 = Color(0xFF2563EB);
  static const chartTone3 = Color(0xFF06B6D4);
  static const chartTone4 = Color(0xFFA5F3FC);

  static const riskHighBg = Color(0xFFFEE2E2);
  static const riskHighText = Color(0xFFDC2626);
  static const riskMediumBg = Color(0xFFFEF3C7);
  static const riskMediumText = Color(0xFFD97706);
  static const riskLowBg = Color(0xFFDCFCE7);
  static const riskLowText = Color(0xFF16A34A);
}

(Color background, Color text) _riskTint(double riskPercent) {
  if (riskPercent >= 70) {
    return (_DashboardColors.riskHighBg, _DashboardColors.riskHighText);
  }
  if (riskPercent >= 40) {
    return (_DashboardColors.riskMediumBg, _DashboardColors.riskMediumText);
  }
  return (_DashboardColors.riskLowBg, _DashboardColors.riskLowText);
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
    this.onReturnToHub,
    this.onSignOut,
    this.initialMetrics,
    this.initialRiskDistribution,
    this.initialModelComparisons,
    this.initialApprovalQueue,
    this.onDownloadSnapshot,
    this.onApproveSlip,
  });

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

  /// Persists/exports the current analytics snapshot. When omitted, the
  /// button just surfaces a confirmation snackbar (demo behavior).
  final Future<void> Function()? onDownloadSnapshot;

  /// Called when a queue slip is approved (tapped), by slip id. When
  /// omitted, only local state is mutated (demo behavior).
  final Future<void> Function(String slipId)? onApproveSlip;

  @override
  State<GuidanceCounselorDashboard> createState() =>
      _GuidanceCounselorDashboardState();
}

class _GuidanceCounselorDashboardState
    extends State<GuidanceCounselorDashboard> {
  final _tabController = GuidanceCounselorDashboardController();

  // Backs the Settings popover's "Dark Mode" switch — same pattern as the
  // Discipline Officer module, whose SettingsPopover this dashboard reuses.
  final _themeMode = ValueNotifier(ThemeMode.light);

  final List<NotificationItemModel> _notifications = <NotificationItemModel>[];

  late GuidanceCounselorMetricsModel _metrics;
  late RiskDistributionModel _riskDistribution;
  late List<ModelMetricModel> _modelComparisons;
  late List<StudentRiskQueueItemModel> _approvalQueue;

  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _metrics = widget.initialMetrics ?? GuidanceCounselorMockData.getSummaryMetrics();
    _riskDistribution = widget.initialRiskDistribution ??
        GuidanceCounselorMockData.getRiskDistribution();
    _modelComparisons = widget.initialModelComparisons ??
        GuidanceCounselorMockData.getModelComparisons();
    _approvalQueue = List.of(
      widget.initialApprovalQueue ?? GuidanceCounselorMockData.getApprovalQueue(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  void _markAllNotificationsRead() {
    setState(() {
      for (var i = 0; i < _notifications.length; i++) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    });
  }

  // Every popover below opens through the shared showHeaderPopover() from
  // discipline_officer_module — same fixed top-right anchor, same
  // HeaderPopoverCard/PopoverHeaderBar chrome — so Notifications, Settings,
  // and Account render pixel-identical to the Discipline Officer header.

  void _openSettings() {
    showHeaderPopover(
      context: context,
      contentBuilder: (popoverContext, setPopoverState) {
        return SettingsPopover(themeModeController: _themeMode);
      },
    );
  }

  void _openProfile() {
    showHeaderPopover(
      context: context,
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
    showHeaderPopover(
      context: context,
      contentBuilder: (popoverContext, setPopoverState) {
        return NotificationsPopover(
          notifications: _notifications,
          accentColor: _DashboardColors.primaryAction,
          onMarkAllRead: () {
            _markAllNotificationsRead();
            setPopoverState(() {});
          },
          onViewAll: () => Navigator.of(popoverContext).pop(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, child) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: _DashboardColors.headerBackground,
            brightness: mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          ),
          child: child!,
        );
      },
      child: Scaffold(
        backgroundColor: _DashboardColors.surfaceBackground,
        body: Column(
          children: [
            AppHeaderNavBar(
              title: 'Guidance Counselor Dashboard',
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
                      color: _DashboardColors.headerChrome,
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
                  icon: Icons.notifications_outlined,
                  badgeCount: unreadCount,
                  onTap: _showNotificationsMenu,
                ),
                HeaderIconButton(
                  icon: Icons.settings_outlined,
                  onTap: _openSettings,
                ),
                ProfileAvatarButton(onTap: _openProfile),
              ],
            ),
            // Tab bar + main content share the same 1440px-capped, centered
            // frame every dashboard module uses (see DashboardPageWrapper).
            Expanded(
              child: DashboardPageWrapper(
                child: Column(
                  children: [
                    ValueListenableBuilder<GuidanceCounselorTab>(
                      valueListenable: _tabController,
                      builder: (context, activeTab, _) {
                        return DashboardHeaderNavBar(
                          activeTab: activeTab,
                          onTabSelected: (tab) => _tabController.value = tab,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ValueListenableBuilder<GuidanceCounselorTab>(
                        valueListenable: _tabController,
                        builder: (context, activeTab, _) {
                          return _buildTabContent(activeTab);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(GuidanceCounselorTab activeTab) {
    return switch (activeTab) {
      GuidanceCounselorTab.overview => _OverviewTab(
          metrics: _metrics,
          riskDistribution: _riskDistribution,
          modelComparisons: _modelComparisons,
          approvalQueue: _approvalQueue,
          downloading: _downloading,
          onDownloadSnapshot: _handleDownloadSnapshot,
          onApproveSlip: _handleApproveSlip,
        ),
      GuidanceCounselorTab.singleStudentAnalysis => const SingleStudentAnalysisView(),
      GuidanceCounselorTab.batchStudentAnalysis => const BatchStudentAnalysisView(),
    };
  }
}

// Account/Logout/Notifications/Settings popovers are the shared
// discipline_officer_module widgets (AccountProfileMenu,
// LogoutConfirmationDialog, NotificationsPopover, SettingsPopover) reused
// verbatim below — see _openProfile / _openSettings / _showNotificationsMenu.

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
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _DashboardColors.navBarBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _DashboardColors.navBarBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        // Stretch so each item's indicator (Positioned bottom: 0) lands
        // flush on the bar's own bottom edge rather than being inset by the
        // row's vertical centering.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tab in GuidanceCounselorTab.values) ...[
            _NavBarItem(
              label: tab.label,
              isActive: activeTab == tab,
              onTap: () => onTabSelected(tab),
            ),
            if (tab != GuidanceCounselorTab.values.last) const SizedBox(width: 28),
          ],
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
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
  });

  final GuidanceCounselorMetricsModel metrics;
  final RiskDistributionModel riskDistribution;
  final List<ModelMetricModel> modelComparisons;
  final List<StudentRiskQueueItemModel> approvalQueue;
  final bool downloading;
  final VoidCallback onDownloadSnapshot;
  final ValueChanged<StudentRiskQueueItemModel> onApproveSlip;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackColumns = constraints.maxWidth < 1000;

        if (stackColumns) {
          return SingleChildScrollView(
            child: Column(
              children: [
                analytics,
                const SizedBox(height: 20),
                SizedBox(height: 520, child: queue),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: SingleChildScrollView(child: analytics)),
            const SizedBox(width: 20),
            SizedBox(width: 360, child: queue),
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricsRow(metrics: metrics),
        const SizedBox(height: 20),
        _RiskDistributionCard(
          distribution: riskDistribution,
          downloading: downloading,
          onDownloadSnapshot: onDownloadSnapshot,
        ),
        const SizedBox(height: 20),
        _ModelComparisonCard(models: modelComparisons),
      ],
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
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: cards.map((c) => SizedBox(width: 260, height: 92, child: c)).toList(),
          );
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _DashboardColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _DashboardColors.cardBorder),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _DashboardColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _DashboardColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: _DashboardColors.mutedIcon, size: 22),
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
          Row(
            children: [
              Text(
                'Risk Distribution',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _DashboardColors.primaryText,
                ),
              ),
              const Spacer(),
              _PrimaryActionButton(
                label: 'Download Data Snapshot',
                icon: Icons.download_rounded,
                loading: downloading,
                onPressed: onDownloadSnapshot,
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 420;
              final donut = _DonutChart(
                segments: [
                  for (var i = 0; i < _slices.length; i++)
                    _ChartSegment(value: values[i].toDouble(), color: _slices[i].$2),
                ],
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trained Model Comparison card (grouped bar chart)
// ---------------------------------------------------------------------------

class _ModelComparisonCard extends StatelessWidget {
  const _ModelComparisonCard({required this.models});

  final List<ModelMetricModel> models;

  static const _seriesLegend = [
    ('roc_auc', _DashboardColors.chartTone1),
    ('pr_auc', _DashboardColors.chartTone2),
    ('recall', _DashboardColors.chartTone3),
    ('f1', _DashboardColors.chartTone4),
  ];

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trained Model Comparison',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _DashboardColors.primaryText,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _GroupedBarChart(models: models)),
              const SizedBox(width: 24),
              const _ChartLegend(entries: _seriesLegend),
            ],
          ),
        ],
      ),
    );
  }
}

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
        color: _DashboardColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _DashboardColors.cardBorder),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          else
            Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
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
                decoration: BoxDecoration(color: entry.$2, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                entry.$1,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _DashboardColors.primaryText,
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
  const _DonutChart({required this.segments});

  final List<_ChartSegment> segments;

  static const _size = 180.0;
  static const _strokeWidth = 30.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: CustomPaint(
        painter: _DonutChartPainter(segments: segments, strokeWidth: _strokeWidth),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({required this.segments, required this.strokeWidth});

  final List<_ChartSegment> segments;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (total <= 0) {
      final paint = Paint()
        ..color = _DashboardColors.gridLine
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
    return oldDelegate.segments != segments || oldDelegate.strokeWidth != strokeWidth;
  }
}

// ---------------------------------------------------------------------------
// Grouped bar chart
// ---------------------------------------------------------------------------

class _GroupedBarChart extends StatelessWidget {
  const _GroupedBarChart({required this.models});

  final List<ModelMetricModel> models;

  static const chartHeight = 220.0;
  static const _ticks = [1.0, 0.8, 0.6, 0.4, 0.2, 0.0];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final tick in _ticks)
                      Text(
                        tick == tick.roundToDouble() ? '${tick.toInt()}' : '$tick',
                        style: GoogleFonts.poppins(fontSize: 10, color: _DashboardColors.secondaryText),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i < _ticks.length; i++)
                          Container(height: 1, color: _DashboardColors.gridLine),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final model in models)
                          _BarGroup(model: model, maxHeight: chartHeight),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const SizedBox(width: 36),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final model in models)
                    Text(
                      model.modelName,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _DashboardColors.primaryText,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BarGroup extends StatelessWidget {
  const _BarGroup({required this.model, required this.maxHeight});

  final ModelMetricModel model;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final values = [model.rocAuc, model.prAuc, model.recall, model.f1];
    const colors = [
      _DashboardColors.chartTone1,
      _DashboardColors.chartTone2,
      _DashboardColors.chartTone3,
      _DashboardColors.chartTone4,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++) ...[
          _Bar(value: values[i], color: colors[i], maxHeight: maxHeight),
          if (i != values.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, required this.maxHeight});

  final double value;
  final Color color;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: maxHeight * value.clamp(0, 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Approval Queue sidebar
// ---------------------------------------------------------------------------

class _ApprovalQueueCard extends StatefulWidget {
  const _ApprovalQueueCard({required this.items, required this.onApprove});

  final List<StudentRiskQueueItemModel> items;
  final ValueChanged<StudentRiskQueueItemModel> onApprove;

  @override
  State<_ApprovalQueueCard> createState() => _ApprovalQueueCardState();
}

class _ApprovalQueueCardState extends State<_ApprovalQueueCard> {
  final _searchController = TextEditingController();
  String _query = '';

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

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _DashboardColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _DashboardColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
              '${widget.items.length} pending slips · Oldest first',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: _DashboardColors.secondaryText,
              ),
            ),
            const SizedBox(height: 14),
            _QueueSearchField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: filtered.isEmpty
                  ? const _QueueEmptyState()
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return _QueueItemTile(
                          item: item,
                          onTap: () => widget.onApprove(item),
                        );
                      },
                    ),
            ),
          ],
        ),
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
      style: GoogleFonts.poppins(fontSize: 13, color: _DashboardColors.primaryText),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search',
        hintStyle: GoogleFonts.poppins(fontSize: 13, color: _DashboardColors.mutedIcon),
        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _DashboardColors.mutedIcon),
        filled: true,
        fillColor: _DashboardColors.searchFill,
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
                    Icons.task_alt_rounded,
                    size: 40,
                    color: _DashboardColors.emptyStateIcon,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No pending evaluation slips',
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

class _QueueItemTile extends StatelessWidget {
  const _QueueItemTile({required this.item, required this.onTap});

  final StudentRiskQueueItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeText) = _riskTint(item.riskPercent);
    final riskLabel = '${item.riskPercent.toStringAsFixed(0)}% Risk';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _DashboardColors.queueItemBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.studentName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _DashboardColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.courseSection,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                  Text(
                    item.studentId,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: _DashboardColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                riskLabel,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: badgeText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

