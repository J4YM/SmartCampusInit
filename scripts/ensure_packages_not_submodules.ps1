# Run from repo root in PowerShell if Git still lists packages as submodules.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

foreach ($pkg in @("packages/kiosk_home", "packages/student_kiosk_module")) {
  $gitMeta = Join-Path $pkg ".git"
  if (Test-Path $gitMeta) {
    Write-Host "Removing nested git metadata: $gitMeta"
    Remove-Item -Recurse -Force $gitMeta
  }
}

if (Test-Path ".gitmodules") {
  Write-Host "Remove .gitmodules manually or: git rm -f .gitmodules"
}

Write-Host "If index still shows submodules, run in Git Bash: bash scripts/ensure_packages_not_submodules.sh"
Write-Host "Then: git add packages/kiosk_home packages/student_kiosk_module && git commit"
