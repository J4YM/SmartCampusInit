import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'slip/slip_lookup_page.dart';
import 'util/load_local_env.dart';

/// Standalone entry point for the admission slip QR-code destination
/// (`/slip/<id>`) — deployed SEPARATELY from the main app (see
/// `netlify.toml`'s redirect rule and `scripts/netlify_build.sh`'s second
/// build step), not as a route inside it. The main app has no URL routing
/// at all today (`lib/main.dart` just swaps widgets in-memory), so a real
/// openable-by-phone-camera URL needed its own small build rather than
/// retrofitting routing everywhere — same reasoning as `main_kiosk.dart`
/// already being a separate entry for the physical kiosk device.
///
/// `usePathUrlStrategy()` is what makes `Uri.base` reflect the real
/// `/slip/<id>` path instead of Flutter web's default hash-based routing.
Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  await loadLocalEnv();
  AppEnv.resolve();

  if (AppEnv.supabaseConfigured) {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      anonKey: AppEnv.supabaseAnonKey,
    );
  }

  runApp(const SlipLookupApp());
}

class SlipLookupApp extends StatelessWidget {
  const SlipLookupApp({super.key});

  /// e.g. `/slip/1234-...` -> `1234-...`. Anything else (no id segment,
  /// wrong path) is treated as a malformed link — `SlipLookupPage` shows
  /// that as an error rather than crashing.
  String? get _slipIdFromUrl {
    final segments = Uri.base.pathSegments;
    if (segments.length >= 2 && segments[0] == 'slip') {
      return segments[1];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admission Slip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: SlipLookupPage(slipId: _slipIdFromUrl),
    );
  }
}
