[Setup]
AppId={{8E9A71D4-4C3B-4A61-9B72-5A0E8C12F901}
AppName=Sao Mai VinTrans
AppVersion=1.0.0
AppVerName=Sao Mai VinTrans 1.0.0
AppPublisher=Cong ty CP TM Xi Mang Sao Mai
DefaultDirName={autopf}\SaoMai_TaiXe
DefaultGroupName=Sao Mai VinTrans
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputBaseFilename=SaoMai_TaiXe_Setup_x64
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\SaoMai_TaiXe.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\SaoMai_TaiXe.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Sao Mai VinTrans"; Filename: "{app}\SaoMai_TaiXe.exe"
Name: "{autodesktop}\Sao Mai VinTrans"; Filename: "{app}\SaoMai_TaiXe.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\SaoMai_TaiXe.exe"; Description: "{cm:LaunchProgram,Sao Mai VinTrans}"; Flags: nowait postinstall skipifsilent
