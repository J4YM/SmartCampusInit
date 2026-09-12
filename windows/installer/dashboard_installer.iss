; STI Baliuag Dashboard — Inno Setup installer script.
;
; Packages the Windows release build of lib/main.dart (the main
; login-gated dashboard app — Registrar, IT Technician, Admin, etc. all
; sign in through this entrypoint) into a proper setup.exe: Start Menu
; shortcut, uninstaller, Programs & Features entry. Sibling to
; kiosk_installer.iss, which packages the separate lib/main_kiosk.dart
; entrypoint the same way.
;
; Prerequisite (one-time, on whichever machine builds the installer):
; install Inno Setup from https://jrsoftware.org/isinfo.php (free), which
; provides ISCC.exe (the command-line compiler this script is built with).
;
; IMPORTANT: lib/main.dart resolves to the same file-based env loader on
; Windows that lib/main_kiosk.dart uses (lib/util/load_local_env_io.dart
; — both go through the conditional lib/util/load_local_env.dart export,
; which only differs between web and native, not between entrypoints).
; So this installer copies .env into the install folder directly (see
; [Files] below) and every shortcut sets WorkingDir explicitly to {app},
; exactly like kiosk_installer.iss does and for the same reason.
;
; Build steps:
;   1. Make sure the repo root's .env has real SUPABASE_URL/SUPABASE_ANON_KEY.
;   2. From the repo root: flutter build windows --release
;      (lib/main.dart is the default entrypoint — no --target override
;      needed, unlike the kiosk build.)
;   3. From this directory: iscc dashboard_installer.iss
;   4. Output: windows/installer/Output/STI_Baliuag_Dashboard_Setup.exe
;
; Re-run all three steps whenever app code OR .env changes.

#define MyAppName "STI Baliuag Dashboard"
#define MyAppPublisher "STI College Baliuag"
#define MyAppExeName "capstone_dashboard.exe"
; Bump this alongside pubspec.yaml's version when the dashboard app changes.
#define MyAppVersion "1.0.0"

[Setup]
AppId={{A3E7B2D4-9F1C-4A8E-B5D2-7C6F0E3A8B91}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Deployed on staff PCs administered by IT staff — install for all users,
; same as the kiosk installer.
PrivilegesRequired=admin
OutputBaseFilename=STI_Baliuag_Dashboard_Setup
OutputDir=Output
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; Everything flutter build windows produces: the exe, flutter_windows.dll,
; plugin DLLs, and the data\ folder.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; The repo root's .env, copied alongside the exe — see the IMPORTANT note
; above for why this (not a bundled asset) is what the app actually reads
; at runtime. Overwritten on every reinstall/upgrade so the deployed app
; always matches the source repo's current Supabase config.
Source: "..\..\.env"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
