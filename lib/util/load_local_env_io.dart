import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Desktop (and other non-web) targets. Prefers a loose `.env` file next
/// to the executable when one exists — this is what lets a developer
/// running `flutter run -d windows` from the repo root pick up the
/// project's own `.env` instantly, and lets a deployed install be
/// repointed at a different Supabase project later without a full
/// rebuild — but falls back to the value already baked into the
/// compiled asset bundle at build time (the same `rootBundle`-based
/// mechanism load_local_env_web.dart always used) when no loose file is
/// present. The Windows installer scripts deliberately stopped shipping
/// a loose `.env` alongside the exe so the install directory doesn't
/// have a plain-text file listing the Supabase URL/anon key sitting
/// next to it — see each installer .iss's own note on why that's a
/// "raise the casual-discovery bar" measure, not real secret protection
/// (the same value is still sitting in the compiled asset bundle,
/// extractable by anyone who knows how to unpack one).
Future<void> loadLocalEnv() async {
  final file = File('.env');
  if (await file.exists()) {
    dotenv.testLoad(fileInput: await file.readAsString());
    return;
  }
  await dotenv.load(fileName: '.env', isOptional: true);
}
