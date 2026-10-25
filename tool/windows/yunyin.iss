; 云音 Windows 安装程序（Inno Setup 6）。
; 固定的 AppId 让新版本识别并覆盖已安装的旧版本；按用户安装，应用内更新无需管理员权限。
; 用法：VERSION=1.1.0 ISCC tool\windows\yunyin.iss（在 flutter build windows --release 之后运行）

#define AppVersion GetEnv("VERSION")
#if AppVersion == ""
  #define AppVersion "0.0.0"
#endif
; 文件版本号只能是数字，去掉 -dev 之类的后缀。
#if Pos("-", AppVersion) > 0
  #define NumVersion Copy(AppVersion, 1, Pos("-", AppVersion) - 1)
#else
  #define NumVersion AppVersion
#endif
#define AppGuid "{8F3C2A51-6E4B-4C1D-9B7A-2D5E8F1A3C64}"

[Setup]
AppId={{#AppGuid}
AppName=云音
AppVersion={#AppVersion}
AppVerName=云音 {#AppVersion}
VersionInfoVersion={#NumVersion}
AppPublisher=Marginal-Z
AppPublisherURL=https://github.com/Marginal-Z/YUNYIN
AppSupportURL=https://github.com/Marginal-Z/YUNYIN/issues
AppUpdatesURL=https://github.com/Marginal-Z/YUNYIN/releases
DefaultDirName={autopf}\YunYin
DefaultGroupName=云音
DisableProgramGroupPage=yes
DisableDirPage=auto
UsePreviousAppDir=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=YunYin-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\yunyin.exe
UninstallDisplayName=云音
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no

[Languages]
; ChineseSimplified.isl 由 CI 按编译器版本准备（Inno Setup 6 只把它作为非官方翻译单独发布）。
Name: "zh"; MessagesFile: "ChineseSimplified.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; 旧版本的资源目录整体替换，避免残留已删除的文件。
Type: filesandordirs; Name: "{app}\data"

[Icons]
Name: "{autoprograms}\云音"; Filename: "{app}\yunyin.exe"
Name: "{autodesktop}\云音"; Filename: "{app}\yunyin.exe"; Tasks: desktopicon

[Run]
; 静默安装（应用内更新）时也会执行，从而在更新完成后重新打开云音。
Filename: "{app}\yunyin.exe"; Description: "{cm:LaunchProgram,云音}"; Flags: nowait postinstall

[Code]
// 只允许高版本覆盖低版本：已安装的版本更新时拒绝降级。
function InstalledVersion(var V: String): Boolean;
var
  Key: String;
begin
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#AppGuid}_is1';
  Result := RegQueryStringValue(HKCU, Key, 'DisplayVersion', V) or RegQueryStringValue(HKLM, Key, 'DisplayVersion', V);
end;

function InitializeSetup(): Boolean;
var
  Prev: String;
  A, B: Int64;
begin
  Result := True;
  if InstalledVersion(Prev) and StrToVersion(Prev, A) and StrToVersion('{#NumVersion}', B) and (ComparePackedVersion(A, B) > 0) then
  begin
    if WizardSilent() then
      Result := False
    else
      Result := MsgBox('已安装更高版本的云音（' + Prev + '），确定要安装旧版本 {#AppVersion} 吗？', mbConfirmation, MB_YESNO) = IDYES;
  end;
end;
