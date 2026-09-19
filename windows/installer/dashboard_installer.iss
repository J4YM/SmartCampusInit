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
; IMPORTANT: lib/main.dart resolves to lib/util/load_local_env_io.dart on
; Windows (the conditional lib/util/load_local_env.dart export only
; differs between web and native, not between entrypoints), same as
; lib/main_kiosk.dart. That loader reads the Supabase URL/anon key from
; the compiled asset bundle (data\flutter_assets\.env, baked in by
; `flutter build` from the repo root's .env at build time) — the SAME
; mechanism the web build has always used — falling back to a loose
; `.env` next to the exe only if one happens to be present. This
; installer deliberately does NOT ship that loose file: it would sit as
; a plain-text file listing the Supabase URL/anon key directly in the
; install directory, trivially readable by anyone browsing it. This is
; not real secret protection either way — the same value is still in
; the compiled asset bundle, extractable by anyone who knows how to
; unpack one — it just means opening the install folder in Explorer
; doesn't turn up an obviously-named .env file. Every shortcut still
; sets WorkingDir explicitly to {app}, matching kiosk_installer.iss.
;
; Build steps:
;   1. Make sure the repo root's .env has real SUPABASE_URL/SUPABASE_ANON_KEY
;      — it gets baked into the build in step 2, so this must happen first.
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
; No separate .env entry — see the IMPORTANT note above: it's already
; inside data\flutter_assets\.env, part of the Release\* tree above.

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
