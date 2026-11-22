; Alfaheem for Windows: the Inno Setup 6 installer (Learning Hub Phase 8, N2; docs/release/WINDOWS.md).
; Built by scripts/release/package_windows.ps1, which passes the defines below:
;   ISCC.exe /DAppVersion=1.0.0 /DAppBuild=1 /DSourceDir=<abs Release folder> /DOutputDir=<abs> /DOutputName=<name> nextbrain.iss
;
; Unsigned (D-1361): SmartScreen warns on the first run until a code-signing certificate exists (WINDOWS.md).
; Per-user by default (no admin prompt, %LOCALAPPDATA%\Programs\Alfaheem); "Install for all users" stays available
; from the privileges dialog / the /ALLUSERS switch. AppId is FIXED: never change it, or a new version installs beside
; the old one instead of upgrading it.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppBuild
  #define AppBuild "0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\releases"
#endif
#ifndef OutputName
  #define OutputName "Alfaheem-" + AppVersion + "-" + AppBuild + "-windows-x64-setup"
#endif

#define AppName "Alfaheem"
#define AppExe "alfaheem.exe"
#define AppPublisher "DoubleY"
; the folder path_provider uses for getApplicationSupportDirectory(): %APPDATA%\<CompanyName>\<ProductName> from
; windows/runner/Runner.rc (the device database nb_local_v1.db, settings, sign-in)
#define DataDir "{userappdata}\DoubleY\Alfaheem"

[Setup]
AppId={{CFB932BC-74BD-4AD0-856E-030D692F6CD5}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}.{#AppBuild}
VersionInfoProductName={#AppName}
VersionInfoCompany={#AppPublisher}
AppPublisher={#AppPublisher}
AppPublisherURL=https://alfheemacademy.com/
AppSupportURL=https://alfheemacademy.com/
AppUpdatesURL=https://alfheemacademy.com/
AppCopyright=Copyright (C) 2026 {#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
DisableWelcomePage=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=auto
LanguageDetectionMethod=uilanguage
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
; Arabic first: the language when Windows' own is neither (the app's default is Arabic too)
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
english.RemoveData=Also delete Alfaheem's data on this computer (your sign-in, settings and offline progress)?%n%nProgress that has not synced yet will be lost. Choose No to keep it for a later install.
arabic.RemoveData=هل تريد أيضًا حذف بيانات الفهيم من هذا الكمبيوتر (تسجيل الدخول والإعدادات والتقدم دون اتصال)؟%n%nسيضيع التقدم الذي لم تتم مزامنته بعد. اختر "لا" للاحتفاظ بها لتثبيت لاحق.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; an upgrade replaces the whole app folder: no file of an older build is left behind
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// Uninstall: the app folder always goes; the data folder only when the person says so (default No). A silent
// uninstall (/SILENT, /VERYSILENT: the upgrade path, scripts) keeps it.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Dir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    Dir := ExpandConstant('{#DataDir}');
    if DirExists(Dir) and (not UninstallSilent) then
      if MsgBox(CustomMessage('RemoveData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(Dir, True, True, True);
  end;
end;
