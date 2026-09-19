; STI Baliuag IT Technician — Inno Setup installer script.
;
; Packages the Windows release build of lib/main_it_technician.dart (the
; dedicated, no-login IT Technician entrypoint — see that file's doc
; comment) into a proper setup.exe: Start Menu shortcut, uninstaller,
; Programs & Features entry. Sibling to kiosk_installer.iss and
; dashboard_installer.iss, which package their own separate entrypoints
; the same way.
;
; SECURITY NOTE: unlike the kiosk build (RFID gate + admission slip only),
; this entrypoint has NO login and boots straight into the full IT
; Technician Dashboard — the student directory (with PII), student
; create/delete, reader-device configuration, and the ticket queue are
; all reachable to anyone who launches the exe. Every action taken here
; is attributed to a single hardcoded demo technician identity (no real
; audit trail). Only install this on a machine that is itself physically
; access-controlled — treat it like a kiosk terminal, not a general
; workstation.
;
; Prerequisite (one-time, on whichever machine builds the installer):
; install Inno Setup from https://jrsoftware.org/isinfo.php (free), which
; provides ISCC.exe (the command-line compiler this script is built with).
;
; IMPORTANT: main_it_technician.dart's env loading
; (lib/util/load_local_env_io.dart) reads the Supabase URL/anon key from
; the compiled asset bundle (data\flutter_assets\.env, baked in by
; `flutter build` from the repo root's .env at build time), falling back
; to a loose `.env` next to the exe only if one happens to be present.
; This installer deliberately does NOT ship that loose file: it would sit
; as a plain-text file listing the Supabase URL/anon key directly in the
; install directory, trivially readable by anyone browsing it — a real
; concern here specifically, since this build already has no login (see
; the SECURITY NOTE above). This is not real secret protection either
; way — the same value is still in the compiled asset bundle, extractable
; by anyone who knows how to unpack one — it just means opening the
; install folder in Explorer doesn't turn up an obviously-named .env
; file. Every shortcut still sets WorkingDir explicitly to {app}, so the
; app finds its own exe-relative resources regardless of how Windows
; would otherwise default the working directory for a given launch
; method.
;
; Build steps:
;   1. Make sure the repo root's .env has real SUPABASE_URL/SUPABASE_ANON_KEY
;      — it gets baked into the build in step 2, so this must happen first.
;   2. From the repo root: flutter build windows --release --target lib/main_it_technician.dart
;   3. From this directory: iscc it_technician_installer.iss
;   4. Output: windows/installer/Output/STI_Baliuag_IT_Technician_Setup.exe
;
; Re-run all three steps whenever IT Technician code OR .env changes.

#define MyAppName "STI Baliuag IT Technician"
#define MyAppPublisher "STI College Baliuag"
#define MyAppExeName "capstone_dashboard.exe"
; Bump this alongside pubspec.yaml's version when this entrypoint changes.
#define MyAppVersion "1.0.0"

[Setup]
AppId={{D18F6C2A-4E7B-4A1D-9C3E-1B8A5F2D6E90}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; IT Technician PCs are typically administered by IT staff — install for
; all users, same as the kiosk and dashboard installers.
PrivilegesRequired=admin
OutputBaseFilename=STI_Baliuag_IT_Technician_Setup
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
