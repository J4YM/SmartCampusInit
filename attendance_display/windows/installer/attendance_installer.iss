; STI Baliuag Attendance Display — Inno Setup installer script.
;
; Packages the standalone attendance_display Flutter project (the second-
; monitor entrance display — see this project's README.md) into a proper
; setup.exe: Start Menu shortcut, uninstaller, Programs & Features entry.
;
; DEPLOYMENT NOTE: this app runs on its OWN dedicated PC, separate from the
; kiosk machine — see README.md's reader-disambiguation section for why
; (the kiosk's and entrance's RFID readers share the same generic
; VID_FFFF&PID_0035 hardware id, which Windows cannot reliably tell apart
; on one machine). Each machine has exactly one reader, so no
; READER_INSTANCE_HINT/READER_PREFIX juggling is needed on either side.
;
; Unlike main_kiosk.dart (a second entry point inside the root app sharing
; its .env), this is a fully separate Flutter project whose own
; attendance_display/.env is bundled as a Flutter ASSET at build time (see
; pubspec.yaml's `assets: - .env`) — so it's already inside
; build\windows\x64\runner\Release\data\flutter_assets\.env and needs no
; separate [Files] copy step the way the kiosk installer needs.
;
; Prerequisite (one-time, on whichever machine builds the installer):
; install Inno Setup from https://jrsoftware.org/isinfo.php (free), which
; provides ISCC.exe (the command-line compiler this script is built with).
;
; Build steps:
;   1. Make sure attendance_display/.env has real Supabase credentials and
;      this machine's READER_VENDOR_ID/READER_PRODUCT_ID (see .env.example).
;   2. From attendance_display/: flutter build windows --release
;   3. From this directory: iscc attendance_installer.iss
;   4. Output: attendance_display/windows/installer/Output/STI_Baliuag_Attendance_Display_Setup.exe
;
; Re-run all three steps whenever attendance_display code OR .env changes —
; the installer packages whatever's currently in
; build\windows\x64\runner\Release (.env included, since it's baked into
; the asset bundle at build time, not read separately at install/run time).

#define MyAppName "STI Baliuag Attendance Display"
#define MyAppPublisher "STI College Baliuag"
#define MyAppExeName "attendance_display.exe"
; Bump this alongside pubspec.yaml's version when the app changes.
#define MyAppVersion "1.0.0"

[Setup]
AppId={{E7A2C9F4-3B6D-4E1A-9F5C-8D2B6A4E1C7F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; This display has no operator console and runs unattended — install for
; all users, same rationale as the kiosk installer.
PrivilegesRequired=admin
OutputBaseFilename=STI_Baliuag_Attendance_Display_Setup
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
; plugin DLLs, and the data\ folder (which already contains the bundled
; .env asset — see the note above).
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
