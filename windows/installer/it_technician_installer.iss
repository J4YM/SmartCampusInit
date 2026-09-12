; STI Baliuag IT Technician — Inno Setup installer script.
;
; Packages the Windows release build of lib/main_it_technician.dart (the
; dedicated, no-login IT Technician entrypoint — see that file's doc
; comment) into a proper setup.exe: Start Menu shortcut, uninstaller,
; Programs & Features entry. Sibling to kiosk_installer.iss and
; dashboard_installer.iss, which package their own separate entrypoints
; the same way.
;
; Prerequisite (one-time, on whichever machine builds the installer):
; install Inno Setup from https://jrsoftware.org/isinfo.php (free), which
; provides ISCC.exe (the command-line compiler this script is built with).
;
; IMPORTANT: unlike the main dashboard build (and like the kiosk build),
; main_it_technician.dart's env loading (lib/util/load_local_env_io.dart)
; reads .env from a plain File('.env') relative to the process's *working
; directory* at runtime — NOT from the compiled asset bundle. So this
; installer copies .env into the install folder directly (see [Files]
; below) and every shortcut sets WorkingDir explicitly to {app}, so the
; app finds it regardless of how Windows would otherwise default the
; working directory for a given launch method.
;
; Build steps:
;   1. Make sure the repo root's .env has real SUPABASE_URL/SUPABASE_ANON_KEY.
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
; The repo root's .env, copied alongside the exe — see the IMPORTANT note
; above for why this (not the bundled asset) is what the app actually
; reads at runtime. Overwritten on every reinstall/upgrade so the deployed
; app always matches the source repo's current Supabase config.
Source: "..\..\.env"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
