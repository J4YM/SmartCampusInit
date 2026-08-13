#!/usr/bin/env bash
# Netlify / CI: install Flutter 3.24.x Linux SDK, then build web with Supabase from env.
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER_TARBALL="${FLUTTER_TARBALL:-https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz}"

if [[ ! -d flutter/bin ]]; then
  echo "Downloading Flutter SDK..."
  curl -fsSL "$FLUTTER_TARBALL" -o _flutter.tar.xz
  tar xf _flutter.tar.xz
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

flutter build web --release "${DART_DEFINES[@]}"
