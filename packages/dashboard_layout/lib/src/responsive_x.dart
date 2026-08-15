import 'package:flutter/material.dart';

/// Width below which every dashboard module (Discipline Officer, Guidance
/// Counselor, Professor, …) switches from the desktop header — with its
/// inline email/notification/profile icons — to [AppBottomNavBar] carrying
/// those same actions. Matches `AppDimensions.responsiveBreakpoint` in
/// login_module so the app switches layouts at a consistent width.
const double kDashboardMobileBreakpoint = 800;

extension ResponsiveX on BuildContext {
  bool get isMobileWidth =>
      MediaQuery.of(this).size.width < kDashboardMobileBreakpoint;
}
