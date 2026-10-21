#!/usr/bin/env bash
# Builds the signed release APK for sideloading (see android/key.properties).
#
# .env is bundled into the app as an asset, so the ML service settings are
# stripped from it for the duration of the build — the mobile app is
# view-only (student / parent / professor dashboards), has no ML service to
# talk to, and must not carry the retrain API key. The original .env is put
# back on exit, even if the build fails.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f android/key.properties ] || { echo "android/key.properties missing — no keystore to sign with." >&2; exit 1; }
[ -f .env ] || { echo ".env missing." >&2; exit 1; }

cp .env .env.build-backup
trap 'mv -f .env.build-backup .env' EXIT
grep -vE '^[[:space:]]*#?[[:space:]]*(ML_API_BASE_URL|ML_RETRAIN_API_KEY)=' .env.build-backup > .env

flutter build apk --release "$@"

echo "APK: build/app/outputs/flutter-apk/app-release.apk"
