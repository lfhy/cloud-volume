; Inno Setup template for packaging the Flutter Windows release bundle.

#ifndef AppName
  #define AppName "云卷"
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppPublisher
  #define AppPublisher "云卷"
#endif
#ifndef AppInstallDirName
  #define AppInstallDirName "Cloud Volume"
#endif
#ifndef SourceDir
  #error SourceDir must be defined.
#endif
#ifndef OutputDir
  #error OutputDir must be defined.
#endif
#ifndef OutputBaseFilename
  #error OutputBaseFilename must be defined.
#endif
#ifndef ArchitecturesAllowed
  #define ArchitecturesAllowed "x64compatible"
#endif
#ifndef ArchitecturesInstallIn64BitMode
  #define ArchitecturesInstallIn64BitMode "x64compatible"
#endif
#ifndef SignTool
  #define SignTool ""
#endif
#ifndef SignPfxPath
  #define SignPfxPath ""
#endif
#ifndef SignPfxPassword
  #define SignPfxPassword ""
#endif
#ifndef SignTimestampUrl
  #define SignTimestampUrl "http://timestamp.digicert.com"
#endif
#ifndef SignSubject
  #define SignSubject ""
#endif

[Setup]
AppId={{B291B621-9AA2-4E6C-9D2A-1F7E44580757}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppInstallDirName}
; Always show the directory page so upgrades can still override the remembered path.
DisableDirPage=no
DefaultGroupName={#AppName}
ArchitecturesAllowed={#ArchitecturesAllowed}
ArchitecturesInstallIn64BitMode={#ArchitecturesInstallIn64BitMode}
DisableProgramGroupPage=yes
Compression=lzma
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
WizardStyle=modern
UninstallDisplayIcon={app}\cloud-volume.exe
#if SignTool != ""
SignTool=signtool /f "{#SignPfxPath}" /p "{#SignPfxPassword}" /fd sha256 /tr "{#SignTimestampUrl}" /td sha256 $f
#elif SignPfxPath != ""
SignTool=signtool /f "{#SignPfxPath}" /p "{#SignPfxPassword}" /fd sha256 /tr "{#SignTimestampUrl}" /td sha256 $f
#elif SignSubject != ""
SignTool=signtool /n "{#SignSubject}" /fd sha256 /tr "{#SignTimestampUrl}" /td sha256 $f
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\cloud-volume.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\cloud-volume.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\cloud-volume.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
