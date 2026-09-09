; STI Baliuag Kiosk — Inno Setup installer script.
;
; Packages the Windows release build of lib/main_kiosk.dart (the dedicated,
; no-login kiosk entrypoint — see that file's doc comment) into a proper
; setup.exe: Start Menu shortcut, uninstaller, Programs & Features entry.
;
; Prerequisite (one-time, on whichever machine builds the installer):
; install Inno Setup from https://jrsoftware.org/isinfo.php (free), which
; provides ISCC.exe (the command-line compiler this script is built with).
;
; IMPORTANT: unlike the web build (and unlike attendance_display's Windows
; build), main_kiosk.dart's env loading (lib/util/load_local_env_io.dart)
; reads .env from a plain File('.env') relative to the process's *working
; directory* at runtime — NOT from the compiled asset bundle. So this
; installer copies .env into the install folder directly (see [Files]
; below) and every shortcut sets WorkingDir explicitly to {app}, so the
; app finds it regardless of how Windows would otherwise default the
; working directory for a given launch method.
;
; Build steps:
;   1. Make sure the repo root's .env has real SUPABASE_URL/SUPABASE_ANON_KEY
;      (the same file the web build uses — main_kiosk.dart reads it through
;      the same AppEnv as lib/main.dart).
;   2. From the repo root: flutter build windows --release --target lib/main_kiosk.dart
;   3. From this directory: iscc kiosk_installer.iss
;   4. Output: windows/installer/Output/STI_Baliuag_Kiosk_Setup.exe
;
; Re-run all three steps whenever kiosk code OR .env changes — the
; installer packages whatever's currently in build/windows/x64/runner/Release
; and the repo root's current .env.

#define MyAppName "STI Baliuag Kiosk"
#define MyAppPublisher "STI College Baliuag"
#define MyAppExeName "capstone_dashboard.exe"
; Bump this alongside pubspec.yaml's version when the kiosk app changes.
#define MyAppVersion "1.0.0"

[Setup]
AppId={{B6C9C4F1-6D3E-4B9C-9E3A-5C1F2A0E7D4A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Kiosk PCs are typically administered by IT staff — install for all users.
PrivilegesRequired=admin
OutputBaseFilename=STI_Baliuag_Kiosk_Setup
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
; above for why this (not the bundled asset) is what the app actually
; reads at runtime. Overwritten on every reinstall/upgrade so the deployed
; kiosk always matches the source repo's current Supabase config.
Source: "..\..\.env"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
