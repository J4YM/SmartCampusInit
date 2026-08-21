#!/usr/bin/env bash
# Netlify / CI: install Flutter Linux SDK, then build web with Supabase from env.
# Pinned to match local dev (flutter --version) — Flutter 3.24.5 was
# previously pinned here but its bundled flutter_test pins `path` to exactly
# 1.9.0, which conflicts with docx_creator's `path ^1.9.1` requirement and
# makes `flutter pub get` fail outright. 3.41.9's bundled pins resolve
# cleanly against the current dependency graph.
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER_TARBALL="${FLUTTER_TARBALL:-https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.9-stable.tar.xz}"

# Netlify caches this whole directory between builds (see build log:
# "Starting to download cache..."). Guarding purely on `flutter/bin`
# existing means a cached install from a PREVIOUS pin (e.g. the old 3.24.5)
# would silently keep being reused forever, even after this script starts
# pointing at a newer tarball — the exact staleness that caused this pin to
# go unnoticed. Track which tarball produced the cached install and
# re-download whenever that changes.
FLUTTER_VERSION_MARKER="flutter/.installed_from_tarball"
if [[ ! -d flutter/bin ]] || [[ "$(cat "$FLUTTER_VERSION_MARKER" 2>/dev/null || true)" != "$FLUTTER_TARBALL" ]]; then
  echo "Downloading Flutter SDK ($FLUTTER_TARBALL)..."
  rm -rf flutter
  curl -fsSL "$FLUTTER_TARBALL" -o _flutter.tar.xz
  tar xf _flutter.tar.xz
  echo "$FLUTTER_TARBALL" > "$FLUTTER_VERSION_MARKER"
fi

export PATH="$PWD/flutter/bin:$PATH"
flutter config --no-analytics
flutter precache --web

# Asset required by pubspec; Netlify often has no committed .env
if [[ ! -f .env ]]; then
  touch .env
fi

flutter pub get

DART_DEFINES=()
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "Injecting SUPABASE_URL / SUPABASE_ANON_KEY via --dart-define (compile-time for web)."
  DART_DEFINES+=(--dart-define="SUPABASE_URL=${SUPABASE_URL}")
  DART_DEFINES+=(--dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}")
else
  echo "Warning: SUPABASE_URL or SUPABASE_ANON_KEY not set; web build will run without Supabase."
fi

if [[ -n "${PROFILE_ROLE_STUDENT:-}" ]]; then
  DART_DEFINES+=(--dart-define="PROFILE_ROLE_STUDENT=${PROFILE_ROLE_STUDENT}")
fi

if [[ -n "${ML_API_BASE_URL:-}" ]]; then
  DART_DEFINES+=(--dart-define="ML_API_BASE_URL=${ML_API_BASE_URL}")
else
  echo "Warning: ML_API_BASE_URL not set; Guidance Counselor dashboard will run without live ML analysis."
fi

if [[ -n "${ML_RETRAIN_API_KEY:-}" ]]; then
  DART_DEFINES+=(--dart-define="ML_RETRAIN_API_KEY=${ML_RETRAIN_API_KEY}")
else
  echo "Warning: ML_RETRAIN_API_KEY not set; Admin's Retrain Model button will stay disabled."
fi

flutter build web --release "${DART_DEFINES[@]}"
