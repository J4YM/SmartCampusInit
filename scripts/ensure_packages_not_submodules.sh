#!/usr/bin/env bash
# Run once from the repository root if Git still treats path packages as submodules
# (Netlify: "No url found in .gitmodules").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PACKAGES=(
  packages/kiosk_home
  packages/student_kiosk_module
  packages/login_module
  packages/admin_dashboard
  packages/rfid_management_module
  packages/virtual_admission_slip
)

for PKG in "${PACKAGES[@]}"; do
  if [[ -d "$PKG/.git" || -f "$PKG/.git" ]]; then
    echo "Removing nested git metadata in $PKG"
    rm -rf "$PKG/.git"
  fi
done

if [[ -f .gitmodules ]]; then
  echo "Removing tracked .gitmodules (broken or unwanted submodule config)."
  git rm -f .gitmodules 2>/dev/null || rm -f .gitmodules
fi

for PKG in "${PACKAGES[@]}"; do
  if [[ "$(git cat-file -t "HEAD:$PKG" 2>/dev/null || echo missing)" == "commit" ]]; then
    echo "Converting $PKG from submodule gitlink to regular directory in the index..."
    git rm -f --cached "$PKG"
    git add "$PKG"
  fi
done

echo "Done. Review and commit: git status"
