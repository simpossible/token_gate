; Token Gate Windows Installer Script
; Requires Inno Setup Compiler (https://jrsoftware.org/isdl.php)
; Install via: winget install JRSoftware.InnoSetup

#define MyAppName "Token Gate"
#define MyAppVersion GetEnv("TOKEN_GATE_VERSION")
#if MyAppVersion == ""
  #define MyAppVersion "2.0.0"
#endif
#define MyAppPublisher "simpossible"
#define MyAppURL "https://github.com/simpossible/token_gate"
#define MyAppExeName "TokenGate.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
; Custom install dialog
WizardStyle=modern
; Output
OutputBaseFilename=TokenGate-{#MyAppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
; Require admin privileges for proper installation
PrivilegesRequired=admin
; Don't create an "Uninstall" entry in the Start Menu
UninstallDisplayIcon={app}\{#MyAppExeName}
; Architecture
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1

[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: quicklaunchicon

[Run]
; Run the app after installation (optional - user can choose)
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\{#MyAppName}"
Type: filesandordirs; Name: "{userappdata}\.token_gate"

[Code]
// Close running Token Gate instances before installation
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  // Try to close any running TokenGate.exe instances
  Exec('taskkill', '/F /IM TokenGate.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Ignore errors - the app may not be running
end;

// Show a message if we just updated an existing installation
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if IsTaskSelected('desktopicon') then
    begin
      // Desktop icon is already created by [Icons] section
    end;
  end;
end;
