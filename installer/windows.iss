; ============================================================================
; 英语角 English Corner —— Windows 安装包（Inno Setup 6）
;
; 由 .github/workflows/build-windows.yml 调用，也可以在本机手动编译：
;   ISCC.exe /DMyAppVersion=0.3.6 /DSourceDir=<Release 目录绝对路径> windows.iss
;
; 为什么要有它：
;   之前发的 zip 是"绿色版"——要解压、要在文件夹里找 exe、没有开始菜单入口、
;   也没有卸载程序。对普通用户不友好。安装包把这几件事一次解决。
;
; 关于代码签名：
;   本项目没有购买代码签名证书，所以安装包和主程序都未签名，
;   Windows SmartScreen 首次运行仍会拦一次（「更多信息」→「仍要运行」）。
;   要彻底消除只能买证书，这不是脚本能解决的。
; ============================================================================

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

; 打包好的 Release 目录（含 yingsui.exe、DLL、data\、ffmpeg\）
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

#define MyAppName "英语角 English Corner"
#define MyAppPublisher "English Corner"
#define MyAppExeName "yingsui.exe"

[Setup]
; AppId 一旦发布就不能再改，否则会被当成另一个软件（无法覆盖升级）
AppId={{7C3A9E14-2B6D-4F58-9A0E-3D5C1B8F7E42}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\English Corner
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\release-assets
OutputBaseFilename=EnglishCorner-{#MyAppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 只允许 64 位 Windows；主程序是纯 x64 的
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Flutter Windows 桌面端要求 Windows 10 1809 及以上
MinVersion=10.0.17763
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
; 默认"仅当前用户"安装，不弹 UAC —— 免管理员也能装。
; 想装进 Program Files 的用户可以在向导首页切换，由下面的 Overrides 允许。
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; 只有在**装好的 Inno Setup 自带**简体中文语言包时才启用中文界面。
; 语言包必须和 Inno Setup 版本严格对应，自己塞一份不同版本的会编译失败，
; 所以这里宁可退回英文界面，也不冒这个险。
; 由 CI 传 /DUseChinese=1 触发（见 build-windows.yml）。
#ifdef UseChinese
[Languages]
Name: "chinese"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 必须整目录打包：主程序依赖同级的 DLL、data\ 和 ffmpeg\
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 用户数据（Hive 里的课程、短语库）存在 %APPDATA%，这里只删程序目录，
; 不碰用户数据 —— 卸载重装后学习记录还在。
Type: filesandordirs; Name: "{app}"
