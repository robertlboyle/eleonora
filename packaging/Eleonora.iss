; Eleonora installer (Inno Setup 6, as PlanetPDF's). Built by scripts\build-installer.ps1,
; which passes /DAppVersion=… /DStage=… /DOutput=….
;
; Installs for the user who runs it (no administrator; %LOCALAPPDATA%\Programs\Eleonora, where
; scripts\install-dev.ps1 puts development builds too), or for everyone when chosen. The mail
; library is never part of the install: it stays where it is (the one last opened is remembered,
; else %LOCALAPPDATA%\Eleonora\Library), and uninstalling keeps it unless the user asks, typing
; DELETE, at the end of uninstalling (see "Deleting the user's data" in [Code]).
; Silent install for IT: /VERYSILENT /SUPPRESSMSGBOXES (/ALLUSERS for every user).
;
; Eleonora was Eudora until 2.0.0 (docs/RENAME-ELEONORA.md). It keeps Eudora's AppId, so this
; Setup upgrades an installed Eudora 1.x: a copy in a folder named "Eudora" moves to "Eleonora"
; beside it (the old folder, its PATH entry, shortcuts, and file-type registrations removed), a
; copy in a folder of the user's own choosing is upgraded where it is. Eudora 1.x's own updater
; runs this Setup too (with /DIR= its old folder: TargetDir in [Code] moves it on).

#ifndef AppVersion
  #error Run scripts\build-installer.ps1 (AppVersion not given)
#endif

#define AppName "Eleonora"
#define Publisher "Planet Networks"

[Setup]
; (Eudora's, unchanged: Windows sees Eleonora as the same program, upgraded)
AppId={{B4E5D2C1-7A3F-4E8B-9C61-2F0D8A5E7B34}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#Publisher}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#Publisher}
VersionInfoDescription={#AppName} Setup
; The folder was "Eudora 27" before 1.0.0 and "Eudora" in 1.x: an update installs into
; "Eleonora" and removes the old one; a folder of the user's own is upgraded where it is
; (DefaultDir, TargetDir, Upgrading below).
DefaultDirName={code:DefaultDir}
UsePreviousAppDir=no
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; x64 (Intel / AMD; also runs emulated on ARM64 Windows) or arm64 (Windows on ARM: Snapdragon
; and the like). Both share the AppId, so either replaces the other in place.
#ifndef Arch
  #define Arch "x64"
#endif
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0
OutputDir={#Output}
#if Arch == "arm64"
OutputBaseFilename=Eleonora-Setup-{#AppVersion}-arm64
#else
OutputBaseFilename=Eleonora-Setup-{#AppVersion}
#endif
SetupIconFile={#Stage}\icon.ico
UninstallDisplayIcon={app}\eleonora.exe
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardImageFile=images\wizard-164x314.png,images\wizard-192x386.png,images\wizard-246x459.png,images\wizard-273x556.png,images\wizard-328x604.png,images\wizard-355x700.png,images\wizard-410x797.png
WizardSmallImageFile=images\small-55x55.png,images\small-64x68.png,images\small-69x69.png,images\small-83x80.png,images\small-92x97.png,images\small-110x106.png,images\small-119x123.png,images\small-138x140.png
Compression=lzma2/normal
SolidCompression=no
; Eleonora's window is closed for the update (its background download runs from a copy in the
; library and takes the new program up by itself)
CloseApplications=yes
RestartApplications=no
ChangesEnvironment=yes
UsePreviousTasks=no
; (.eml, .msg, .ics, and .vcf are registered below: Explorer is told to look again)
ChangesAssociations=yes

[Files]
Source: "{#Stage}\eleonora.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\eleonora-cli.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\eleonora-web.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\LICENSE-MIT"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\LICENSE-APACHE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\THIRD-PARTY-NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\eleonora.exe"; Comment: "Mail for decades of messages"; AppUserModelID: "net.planet.eleonora"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\eleonora.exe"; Tasks: desktopicon; AppUserModelID: "net.planet.eleonora"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"
Name: "addtopath"; Description: "Let command prompts and scripts run eleonora-cli (adds Eleonora to the PATH)"

[Registry]
; Eleonora opens .eml messages and .ics calendar files, and Outlook .msg files in its message
; viewer: listed under Open with and in Windows' Default apps, where the user picks it (Windows
; lets no program make itself the default). HKA = this user's, or every user's when installed for
; everyone. (Eudora 1.x's own entries are pointed at Eleonora in [Code]:
; RemoveEudoraRegistrations.) (the old program's own entry, eudora27.exe before 1.0.0)
Root: HKA; Subkey: "Software\Classes\Applications\eudora27.exe"; Flags: deletekey dontcreatekey
Root: HKA; Subkey: "Software\Classes\Eleonora.eml"; ValueType: string; ValueName: ""; ValueData: "Email message"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Eleonora.eml\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\eleonora.exe,0"
Root: HKA; Subkey: "Software\Classes\Eleonora.eml\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\eleonora.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Eleonora.msg"; ValueType: string; ValueName: ""; ValueData: "Outlook message"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Eleonora.msg\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\eleonora.exe,0"
Root: HKA; Subkey: "Software\Classes\Eleonora.msg\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\eleonora.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Eleonora.ics"; ValueType: string; ValueName: ""; ValueData: "Calendar file"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Eleonora.ics\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\eleonora.exe,0"
Root: HKA; Subkey: "Software\Classes\Eleonora.ics\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\eleonora.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.eml\OpenWithProgids"; ValueType: string; ValueName: "Eleonora.eml"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.ics\OpenWithProgids"; ValueType: string; ValueName: "Eleonora.ics"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.msg\OpenWithProgids"; ValueType: string; ValueName: "Eleonora.msg"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\eleonora.exe\SupportedTypes"; ValueType: string; ValueName: ".eml"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\eleonora.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "Eleonora"
Root: HKA; Subkey: "Software\Classes\Applications\eleonora.exe\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\eleonora.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\eleonora.exe\SupportedTypes"; ValueType: string; ValueName: ".ics"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\eleonora.exe\SupportedTypes"; ValueType: string; ValueName: ".msg"; ValueData: ""
Root: HKA; Subkey: "Software\Planet Networks\Eleonora\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Eleonora"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Planet Networks\Eleonora\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Mail for decades of messages"
Root: HKA; Subkey: "Software\Planet Networks\Eleonora\Capabilities\FileAssociations"; ValueType: string; ValueName: ".eml"; ValueData: "Eleonora.eml"
Root: HKA; Subkey: "Software\Planet Networks\Eleonora\Capabilities\FileAssociations"; ValueType: string; ValueName: ".ics"; ValueData: "Eleonora.ics"
; vcf contact cards: add or update each contact
Root: HKA; Subkey: "Software\Classes\Eleonora.vcf"; ValueType: string; ValueName: ""; ValueData: "Contact card"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Eleonora.vcf\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\eleonora.exe,0"
Root: HKA; Subkey: "Software\Classes\Eleonora.vcf\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\eleonora.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.vcf\OpenWithProgids"; ValueType: string; ValueName: "Eleonora.vcf"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\eleonora.exe\SupportedTypes"; ValueType: string; ValueName: ".vcf"; ValueData: ""
Root: HKA; Subkey: "Software\Planet Networks\Eleonora\Capabilities\FileAssociations"; ValueType: string; ValueName: ".vcf"; ValueData: "Eleonora.vcf"
Root: HKA; Subkey: "Software\Planet Networks\Eleonora\Capabilities\FileAssociations"; ValueType: string; ValueName: ".msg"; ValueData: "Eleonora.msg"
; mailto: links: a URL protocol class, offered in Default apps as the mail program
Root: HKA; Subkey: "Software\Classes\Eleonora.mailto"; ValueType: string; ValueName: ""; ValueData: "URL:MailTo Protocol"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Eleonora.mailto"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Eleonora.mailto\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\eleonora.exe,0"
Root: HKA; Subkey: "Software\Classes\Eleonora.mailto\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\eleonora.exe"" ""%1"""
Root: HKA; Subkey: "Software\Planet Networks\Eleonora\Capabilities\URLAssociations"; ValueType: string; ValueName: "mailto"; ValueData: "Eleonora.mailto"
Root: HKA; Subkey: "Software\Clients\Mail\Eleonora"; ValueType: string; ValueName: ""; ValueData: "Eleonora"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Clients\Mail\Eleonora\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Eleonora"
Root: HKA; Subkey: "Software\Clients\Mail\Eleonora\Capabilities\URLAssociations"; ValueType: string; ValueName: "mailto"; ValueData: "Eleonora.mailto"
Root: HKA; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "Eleonora"; ValueData: "Software\Planet Networks\Eleonora\Capabilities"; Flags: uninsdeletevalue

[InstallDelete]
; development builds' old copies (scripts\install-dev.ps1 renames the one replaced)
Type: files; Name: "{app}\*.old"
; the folder Eudora was installed in before 1.0.0 (its window is closed first: PrepareToInstall)
Type: filesandordirs; Name: "{autopf}\Eudora 27"

[Run]
; (as the user who ran Setup, never with the administrator rights an install for everyone has: 2026-11-11, the
; Eudora that 1.0.0's Setup started this way ran elevated on the library)
Filename: "{app}\eleonora.exe"; Description: "Start Eleonora"; Flags: nowait postinstall skipifsilent runasoriginaluser
; an update Eleonora (or Eudora 1.x) started (Restart Now: /SILENT … /relaunch=1;
; eleonora-core/src/update.rs) starts Eleonora again, as the user who ran it
Filename: "{app}\eleonora.exe"; Flags: nowait runasoriginaluser; Check: Relaunch

[Code]
{ Started by an update with Restart Now (Eleonora's own, or Eudora 1.x's). }
function Relaunch: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;

{ The PATH: the user's own (installed for me) or everyone's (installed for all users). }
function EnvRoot: Integer;
begin
  if IsAdminInstallMode then Result := HKEY_LOCAL_MACHINE else Result := HKEY_CURRENT_USER;
end;

function EnvKey: String;
begin
  if IsAdminInstallMode then
    Result := 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
  else
    Result := 'Environment';
end;

procedure AddToPath(Folder: String);
var
  Path: String;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', Path) then
    Path := '';
  if Pos(';' + Uppercase(Folder) + ';', ';' + Uppercase(Path) + ';') > 0 then
    exit;
  if (Path <> '') and (Path[Length(Path)] <> ';') then
    Path := Path + ';';
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', Path + Folder);
end;

{ Takes Folder out of the PATH, if it's there. }
procedure RemoveFromPath(Folder: String);
var
  Path: String;
  P: Integer;
begin
  if not RegQueryStringValue(EnvRoot, EnvKey, 'Path', Path) then
    exit;
  P := Pos(';' + Uppercase(Folder) + ';', ';' + Uppercase(Path) + ';');
  if P = 0 then
    exit;
  Delete(Path, P - 1, Length(Folder) + 1);
  if (Length(Path) > 0) and (Path[1] = ';') then
    Delete(Path, 1, 1);
  RegWriteExpandStringValue(EnvRoot, EnvKey, 'Path', Path);
end;

{ Whether Folder is in the PATH. }
function InPath(Folder: String): Boolean;
var
  Path: String;
begin
  Result := RegQueryStringValue(EnvRoot, EnvKey, 'Path', Path) and (Pos(';' + Uppercase(Folder) + ';', ';' + Uppercase(Path) + ';') > 0);
end;

var
  { An Eudora from before 1.0.0 was replaced, and whether its folder was in the PATH (an update
    passes no tasks, /TASKS=, so what the old install had is carried over by hand). }
  ReplacedOld, OldOnPath: Boolean;

{ Eudora before 1.0.0 ran as eudora27.exe from the "Eudora 27" folder: its window is asked to
  close (it then stops its background download), else stopped, so the old folder can go. }
procedure CloseEudora27;
var
  Code, Tries: Integer;
begin
  OldOnPath := InPath(ExpandConstant('{autopf}\Eudora 27'));
  if not FileExists(ExpandConstant('{autopf}\Eudora 27\eudora27.exe')) then
  begin
    { (a PATH entry left by an old install whose folder is already gone goes too) }
    if OldOnPath then
      RemoveFromPath(ExpandConstant('{autopf}\Eudora 27'));
    exit;
  end;
  ReplacedOld := True;
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM eudora27.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Tries := 0;
  while (Tries < 20) and (Exec(ExpandConstant('{sys}\cmd.exe'), '/c tasklist /FI "IMAGENAME eq eudora27.exe" | find /I "eudora27.exe" >nul', '', SW_HIDE, ewWaitUntilTerminated, Code)) and (Code = 0) do
  begin
    Sleep(500);
    Tries := Tries + 1;
  end;
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM eudora27.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  RemoveFromPath(ExpandConstant('{autopf}\Eudora 27'));
end;

{ Upgrading. Every Eudora 1.x or Eleonora installed
  here is found, for everyone (HKLM) and for this user (HKCU), whichever install mode this Setup
  runs in; the copy in use (a running eudora.exe, else the one installed last) is marked and
  chosen on an Upgrade page. Upgrading a copy installed in the other mode starts this Setup again
  in that mode (/ALLUSERS asks Windows for permission; /CURRENTUSER runs as the user) with
  /UPGRADE="folder", which picks it and skips the page. An upgrade skips the folder and task pages
  (its shortcuts and PATH entry stay as they are), and the Ready page says Upgrade. A silent
  update (the updater passes /ALLUSERS or /CURRENTUSER) upgrades the copy of its own mode. An
  install from before 1.0.0 ("Eudora 27") is not one: it goes to the new folder and the old one is
  removed, as above. }
var
  CopyDir, CopyVersion: array of String;
  { CopyAdmin: installed for everyone; CopyEudora: an Eudora 1.x (eudora.exe), not yet Eleonora }
  CopyAdmin, CopyEudora: array of Boolean;
  CopiesFound, Upgrade, Relaunching, Requested: Boolean;
  Chosen, InUse: Integer;
  UpgradePage: TInputOptionWizardPage;

function UninstallKey: String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + ExpandConstant('{#SetupSetting("AppId")}') + '_is1';
end;

procedure AddCopy(Root: Integer; Admin: Boolean);
var
  Dir, Version: String;
  N: Integer;
begin
  if not RegQueryStringValue(Root, UninstallKey, 'Inno Setup: App Path', Dir) then exit;
  { (from before 1.0.0, or a folder that's gone: nothing to upgrade there) }
  if (CompareText(ExtractFileName(RemoveBackslashUnlessRoot(Dir)), 'Eudora 27') = 0) or
    not (FileExists(AddBackslash(Dir) + 'eleonora.exe') or FileExists(AddBackslash(Dir) + 'eudora.exe')) then exit;
  RegQueryStringValue(Root, UninstallKey, 'DisplayVersion', Version);
  N := GetArrayLength(CopyDir);
  SetArrayLength(CopyDir, N + 1);
  SetArrayLength(CopyVersion, N + 1);
  SetArrayLength(CopyAdmin, N + 1);
  SetArrayLength(CopyEudora, N + 1);
  CopyDir[N] := RemoveBackslashUnlessRoot(Dir);
  CopyVersion[N] := Version;
  CopyAdmin[N] := Admin;
  CopyEudora[N] := not FileExists(AddBackslash(Dir) + 'eleonora.exe');
end;

{ Where Eleonora goes when upgrading the copy in Dir: an Eudora 1.x in a folder named "Eudora"
  (Setup's own name for it) moves to "Eleonora" beside it; any other folder is the user's own
  choice and is upgraded where it is. }
function TargetDir(Dir: String): String;
begin
  Dir := RemoveBackslashUnlessRoot(Dir);
  if (CompareText(ExtractFileName(Dir), 'Eudora') = 0) and FileExists(AddBackslash(Dir) + 'eudora.exe') then
    Result := AddBackslash(ExtractFileDir(Dir)) + 'Eleonora'
  else
    Result := Dir;
end;

{ The folder of a running Eleonora (eleonora.exe) or Eudora 1.x (eudora.exe), or ''. }
function RunningFolder: String;
var
  OutFile: String;
  Code: Integer;
  Text: AnsiString;
begin
  Result := '';
  OutFile := ExpandConstant('{tmp}\eudora-running.txt');
  if Exec('powershell.exe', '-NoProfile -NonInteractive -Command "(Get-Process eleonora, eudora -ErrorAction SilentlyContinue | Where-Object Path | Select-Object -First 1).Path | Out-File -Encoding ascii ''' + OutFile + '''"', '', SW_HIDE, ewWaitUntilTerminated, Code)
    and LoadStringFromFile(OutFile, Text) and (Trim(String(Text)) <> '') then
    Result := RemoveBackslashUnlessRoot(ExtractFileDir(Trim(String(Text))));
end;

procedure FindCopies;
var
  I: Integer;
  Running, Asked: String;
  Newest, Stamp: Int64;
  Found: TFindRec;
begin
  if CopiesFound then exit;
  CopiesFound := True;
  AddCopy(HKLM, True);
  AddCopy(HKCU, False);
  InUse := -1;
  Chosen := -1;
  if GetArrayLength(CopyDir) = 0 then exit;
  Asked := RemoveBackslashUnlessRoot(ExpandConstant('{param:UPGRADE|}'));
  Running := RunningFolder;
  Newest := 0;
  for I := 0 to GetArrayLength(CopyDir) - 1 do
  begin
    if (Running <> '') and (CompareText(Running, CopyDir[I]) = 0) then
      InUse := I;
    if (Asked <> '') and (CompareText(Asked, CopyDir[I]) = 0) then
      Chosen := I;
  end;
  Requested := Chosen >= 0;
  if InUse < 0 then
    for I := 0 to GetArrayLength(CopyDir) - 1 do
      if FindFirst(AddBackslash(CopyDir[I]) + 'eleonora.exe', Found) or FindFirst(AddBackslash(CopyDir[I]) + 'eudora.exe', Found) then
      begin
        Stamp := Int64(Found.LastWriteTime.dwHighDateTime) * 4294967296 + Int64(Found.LastWriteTime.dwLowDateTime);
        FindClose(Found);
        if Stamp > Newest then
        begin
          Newest := Stamp;
          InUse := I;
        end;
      end;
  if InUse < 0 then InUse := 0;
  { silent (the updater): the copy of this install mode }
  if (Chosen < 0) and WizardSilent then
    for I := 0 to GetArrayLength(CopyDir) - 1 do
      if CopyAdmin[I] = IsAdminInstallMode then
        Chosen := I;
  Upgrade := Chosen >= 0;
end;

function CopyName(I: Integer): String;
begin
  if CopyEudora[I] then Result := 'Eudora' else Result := 'Eleonora';
end;

function CopyCaption(I: Integer): String;
begin
  Result := 'Upgrade ' + CopyName(I) + ' ' + CopyVersion[I] + ' in ' + CopyDir[I];
  if CompareText(TargetDir(CopyDir[I]), CopyDir[I]) <> 0 then
    Result := Result + ' to Eleonora in ' + TargetDir(CopyDir[I]);
  if CopyAdmin[I] then Result := Result + ' (for everyone' else Result := Result + ' (for you only';
  if (I = InUse) and (GetArrayLength(CopyDir) > 1) then Result := Result + '; the copy you use)' else Result := Result + ')';
end;

function DefaultDir(Param: String): String;
var
  I: Integer;
begin
  FindCopies;
  if Chosen >= 0 then
    Result := TargetDir(CopyDir[Chosen])
  else
  begin
    Result := ExpandConstant('{autopf}\Eleonora');
    for I := 0 to GetArrayLength(CopyDir) - 1 do
      if CopyAdmin[I] = IsAdminInstallMode then Result := TargetDir(CopyDir[I]);
  end;
end;

procedure MakeUpgradePage;
var
  I: Integer;
  Sub, Title, Name: String;
  AnyEudora: Boolean;
begin
  FindCopies;
  if GetArrayLength(CopyDir) = 0 then exit;
  AnyEudora := False;
  for I := 0 to GetArrayLength(CopyDir) - 1 do
    if CopyEudora[I] then AnyEudora := True;
  if AnyEudora then
  begin
    Title := 'Upgrade Eudora to Eleonora';
    Name := 'Eudora';
  end
  else
  begin
    Title := 'Upgrade Eleonora';
    Name := 'Eleonora';
  end;
  if GetArrayLength(CopyDir) > 1 then
    Sub := Name + ' is installed twice on this computer. The copy you use is marked and chosen. Your mail, accounts, and settings are kept either way.'
  else if AnyEudora then
    Sub := 'Eudora is now called Eleonora. Setup will upgrade the copy installed here. Your mail, accounts, settings, and saved passwords are kept, and Eleonora takes them over the first time it starts.'
  else
    Sub := 'Setup will upgrade it where it is. Your mail, accounts, and settings are kept.';
  UpgradePage := CreateInputOptionPage(wpWelcome, Title, Name + ' is already installed on this computer.', Sub, True, False);
  for I := 0 to GetArrayLength(CopyDir) - 1 do
    UpgradePage.Add(CopyCaption(I));
  UpgradePage.Add('Choose another folder instead');
  if Chosen >= 0 then UpgradePage.SelectedValueIndex := Chosen else UpgradePage.SelectedValueIndex := InUse;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (UpgradePage <> nil) and (PageID = UpgradePage.ID) then
    { (started again for a chosen copy: already chosen) }
    Result := Requested
  else if (PageID = wpSelectDir) or (PageID = wpSelectTasks) then
    Result := Upgrade;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I, Code: Integer;
  Params: String;
begin
  Result := True;
  if (UpgradePage = nil) or (CurPageID <> UpgradePage.ID) then exit;
  I := UpgradePage.SelectedValueIndex;
  if I >= GetArrayLength(CopyDir) then
  begin
    Upgrade := False;
    Chosen := -1;
    exit;
  end;
  if CopyAdmin[I] <> IsAdminInstallMode then
  begin
    { that copy was installed in the other mode: Setup again, in that mode }
    Result := False;
    Params := '/UPGRADE="' + CopyDir[I] + '"';
    if CopyAdmin[I] then
      Relaunching := ShellExec('runas', ExpandConstant('{srcexe}'), '/ALLUSERS ' + Params, '', SW_SHOWNORMAL, ewNoWait, Code)
    else
      Relaunching := ExecAsOriginalUser(ExpandConstant('{srcexe}'), '/CURRENTUSER ' + Params, '', SW_SHOWNORMAL, ewNoWait, Code);
    if Relaunching then
      WizardForm.Close
    else
      MsgBox('Setup couldn''t start again to upgrade the copy in ' + CopyDir[I] + ': ' + SysErrorMessage(Code), mbError, MB_OK);
    exit;
  end;
  Chosen := I;
  Upgrade := True;
  WizardForm.DirEdit.Text := TargetDir(CopyDir[I]);
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if Relaunching then Confirm := False;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpReady) and Upgrade then
  begin
    WizardForm.PageNameLabel.Caption := 'Ready to Upgrade';
    WizardForm.PageDescriptionLabel.Caption := Format('%s %s in %s will be upgraded to Eleonora %s.', [CopyName(Chosen), CopyVersion[Chosen], CopyDir[Chosen], '{#AppVersion}']);
    WizardForm.ReadyLabel.Caption := 'Your mail, accounts, and settings are kept. Click Upgrade to continue.';
    WizardForm.NextButton.Caption := 'Upgrade';
  end;
end;

{ Upgrading an Eudora 1.x. OldDir: its folder, when Eleonora goes into a new folder beside it
  (TargetDir); InPlace: it's upgraded in its own folder (one the user chose). Either way its
  window is closed first, and after installing its files, folder, PATH entry, shortcuts, and
  registrations go. }
var
  OldDir: String;
  OldDirOnPath, InPlace: Boolean;

{ Stops eudora.exe / eudora-cli.exe running from Dir: an Eudora that started this update is
  quitting by itself, so it's given 10 s first. (Its background download runs from the library's
  own copy, which Eleonora stops when it first starts and takes the library over.) }
procedure StopEudoraIn(Dir: String);
var
  Code: Integer;
begin
  Exec('powershell.exe', '-NoProfile -NonInteractive -Command "$d = ''' + AddBackslash(Dir) + '''; ' +
    'function Running { Get-Process eudora, eudora-cli -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($d, [StringComparison]::OrdinalIgnoreCase) } }; ' +
    'for ($i = 0; ($i -lt 20) -and (Running); $i++) { Start-Sleep -Milliseconds 500 }; Running | Stop-Process -Force"',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  App, Candidate: String;
begin
  Result := '';
  CloseEudora27;
  App := RemoveBackslashUnlessRoot(WizardDirValue);
  Candidate := AddBackslash(ExtractFileDir(App)) + 'Eudora';
  if (CompareText(ExtractFileName(App), 'Eleonora') = 0) and FileExists(AddBackslash(Candidate) + 'eudora.exe')
    and FileExists(AddBackslash(Candidate) + 'unins000.exe') then
  begin
    OldDir := Candidate;
    OldDirOnPath := InPath(OldDir);
    StopEudoraIn(OldDir);
  end;
  if FileExists(AddBackslash(App) + 'eudora.exe') and FileExists(AddBackslash(App) + 'unins000.exe') then
  begin
    InPlace := True;
    StopEudoraIn(App);
  end;
end;

{ Eudora 1.x's file types, mailto: handler, and Default apps entry, in one part of the registry
  (Root: every user's, or this user's). Only where that Eudora's own key is there: classic Eudora
  7 may own Clients\Mail\Eudora and Applications\eudora.exe.
  The file types themselves (Eudora.eml, .msg, .ics, .mailto) are kept and opened with Eleonora,
  because Windows keeps the user's choice of default program by that name
  (FileExts\.msg\UserChoice = Eudora.msg) and lets no program change it, so a type deleted left
  that choice pointing nowhere, and one left as it was went on starting the old Eudora. Pointed at
  Eleonora, every choice the user made keeps working, with Eleonora's icon. }
procedure CarryOverEudoraRegistrationsIn(Root: Integer);
var
  Kind, Exe: String;
  I: Integer;
begin
  if not RegKeyExists(Root, 'Software\Planet Networks\Eudora') then exit;
  Exe := ExpandConstant('{app}\eleonora.exe');
  for I := 0 to 3 do
  begin
    case I of
      0: Kind := 'eml';
      1: Kind := 'msg';
      2: Kind := 'ics';
    else
      Kind := 'mailto';
    end;
    if RegKeyExists(Root, 'Software\Classes\Eudora.' + Kind) then
    begin
      RegWriteStringValue(Root, 'Software\Classes\Eudora.' + Kind + '\DefaultIcon', '', Exe + ',0');
      RegWriteStringValue(Root, 'Software\Classes\Eudora.' + Kind + '\shell\open\command', '', '"' + Exe + '" "%1"');
    end;
    { (Open with lists Eleonora once, by its own type) }
    if Kind <> 'mailto' then
      RegDeleteValue(Root, 'Software\Classes\.' + Kind + '\OpenWithProgids', 'Eudora.' + Kind);
  end;
  RegDeleteKeyIncludingSubkeys(Root, 'Software\Classes\Applications\eudora.exe');
  RegDeleteKeyIncludingSubkeys(Root, 'Software\Clients\Mail\Eudora');
  RegDeleteValue(Root, 'Software\RegisteredApplications', 'Eudora');
  RegDeleteKeyIncludingSubkeys(Root, 'Software\Planet Networks\Eudora');
end;

procedure RemoveEudoraRegistrations;
begin
  CarryOverEudoraRegistrationsIn(HKA);
  { (installed for everyone: this user's own registrations from an Eudora installed for them, or
    a development copy, go the same way) }
  if IsAdminInstallMode then
    CarryOverEudoraRegistrationsIn(HKCU);
end;

{ An Eudora 1.x left in this user's Programs folder without an uninstaller (a development copy,
  scripts\install-dev.ps1), or one whose uninstaller is gone: stopped, deleted, with its Start
  Menu shortcut, PATH entry, and the program list's entry when it names that folder. Its file
  types were made Eleonora's above. }
procedure RemoveLeftoverEudora;
var
  Dir, Path, Listed: String;
  P: Integer;
begin
  Dir := ExpandConstant('{localappdata}\Programs\Eudora');
  if not FileExists(AddBackslash(Dir) + 'eudora.exe') or FileExists(AddBackslash(Dir) + 'unins000.exe') then exit;
  StopEudoraIn(Dir);
  DelTree(Dir, True, True, True);
  DeleteFile(ExpandConstant('{userprograms}\Eudora.lnk'));
  if RegQueryStringValue(HKCU, 'Environment', 'Path', Path) then
  begin
    P := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Path) + ';');
    if P > 0 then
    begin
      Delete(Path, P - 1, Length(Dir) + 1);
      if (Length(Path) > 0) and (Path[1] = ';') then Delete(Path, 1, 1);
      RegWriteExpandStringValue(HKCU, 'Environment', 'Path', Path);
    end;
  end;
  if RegQueryStringValue(HKCU, UninstallKey, 'Inno Setup: App Path', Listed) and (CompareText(RemoveBackslashUnlessRoot(Listed), Dir) = 0) then
    RegDeleteKeyIncludingSubkeys(HKCU, UninstallKey);
end;

{ After installing: what's left of the Eudora 1.x that was upgraded. }
procedure FinishEudoraUpgrade;
var
  Old: String;
  I: Integer;
begin
  if (OldDir = '') and not InPlace then exit;
  if OldDir <> '' then
  begin
    if OldDirOnPath then
    begin
      RemoveFromPath(OldDir);
      AddToPath(ExpandConstant('{app}'));
    end;
    if FileExists(AddBackslash(OldDir) + 'eudora.exe') and FileExists(AddBackslash(OldDir) + 'unins000.exe') then
      DelTree(OldDir, True, True, True);
    { (the emptied folder itself can be held a moment longer, as Explorer let go of it: on the
      first real upgrade, 2026-11-17, an empty C:\Program Files\Eudora was left; tried for 5 s) }
    for I := 1 to 10 do
      if DirExists(OldDir) and not RemoveDir(OldDir) then Sleep(500);
  end
  else
  begin
    DeleteFile(ExpandConstant('{app}\eudora.exe'));
    DeleteFile(ExpandConstant('{app}\eudora-cli.exe'));
    DeleteFile(ExpandConstant('{app}\eudora-web.exe'));
    { (Eudora's uninstall log in this folder now holds Eleonora's too: Inno appends to it) }
  end;
  DeleteFile(ExpandConstant('{autoprograms}\Eudora.lnk'));
  { a desktop shortcut the user had: Eleonora's in its place }
  Old := ExpandConstant('{autodesktop}\Eudora.lnk');
  if FileExists(Old) then
  begin
    DeleteFile(Old);
    if not WizardIsTaskSelected('desktopicon') then
      CreateShellLink(ExpandConstant('{autodesktop}\Eleonora.lnk'), 'Mail for decades of messages', ExpandConstant('{app}\eleonora.exe'), '', ExpandConstant('{app}'), '', 0, SW_SHOWNORMAL);
  end;
end;

{ Eleonora's window is drawn by Microsoft Edge WebView2, part of Windows 11 and of current
  Windows 10; on a computer without it, say where to get it. }
const WebView2Client = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

function HasWebView2: Boolean;
var
  Version: String;
begin
  Result :=
    (RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\' + WebView2Client, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0')) or
    (RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + WebView2Client, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0')) or
    (RegQueryStringValue(HKCU, 'Software\Microsoft\EdgeUpdate\Clients\' + WebView2Client, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0'));
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if not HasWebView2 then
    Result := MsgBox('Eleonora needs Microsoft Edge WebView2, which this computer doesn''t have yet.' + #13#10#13#10 +
      'Get the "Evergreen Bootstrapper" from https://developer.microsoft.com/microsoft-edge/webview2/ and run it, then run this setup again.' + #13#10#13#10 +
      'Install Eleonora anyway?', mbConfirmation, MB_YESNO) = IDYES;
end;

// "Did you know?" tips on the Installing page, while the files are copied (as PlanetPDF's):
// a new one every TipSeconds, or at once with "Next tip". Keep them true when features change.
const TipSeconds = 8;

var
  Tips: array of String;
  CurrentTip: Integer;
  TipShownAt: DWORD;
  TipHeading, TipText, TipCounter, TipNext: TNewStaticText;

function GetTickCount: DWORD; external 'GetTickCount@kernel32.dll stdcall';

procedure AddTip(Text: String);
begin
  SetArrayLength(Tips, GetArrayLength(Tips) + 1);
  Tips[GetArrayLength(Tips) - 1] := Text;
end;

procedure ShowTip(Index: Integer);
begin
  CurrentTip := Index mod GetArrayLength(Tips);
  TipText.Caption := Tips[CurrentTip];
  TipCounter.Caption := Format('Tip %d of %d', [CurrentTip + 1, GetArrayLength(Tips)]);
  TipShownAt := GetTickCount;
end;

procedure NextTipClick(Sender: TObject);
begin
  ShowTip(CurrentTip + 1);
end;

procedure InitializeWizard;
var
  Page: TNewNotebookPage;
  Gauge: TNewProgressBar;
begin
  AddTip('One library for every account: Microsoft 365, Outlook.com, Gmail, IMAP, and POP3, and your old Eudora mailboxes, all in one window with one search.');
  AddTip('Eleonora is built for huge mailboxes: millions of messages and decades of mail stay fast to open, scroll, and search.');
  AddTip('Search understands Outlook''s words: from:, to:, subject:, hasattachment:yes, received:last week, size:>5MB, and any header, like importance:high.');
  AddTip('The last word you type in Search also finds words that begin with it (walkerfi finds walkerfield.example), and a word ending in * matches only by its start.');
  AddTip('The spam filter sorts arriving mail into Marketing, Notifications, Lists, and Spam, and learns from every Spam and Not Spam you mark.');
  AddTip('Right-click any message and choose "Why?" to see exactly which rule sorted it, then switch that rule off or give it an exception in Mail Filter Rules.');
  AddTip('Views gather Receipts, Invoices, Payments, Travel, Legal, Verification Codes, and Red Alerts from every account, without moving a single message.');
  AddTip('Red Alert keeps the messages you must never miss in sight: shut-off and past-due notices, government letters, security advisories, and urgent mail from people you know.');
  AddTip('Flights, trains, hotels, and tickets in your mail go onto your calendar by themselves, with the boarding pass or ticket attached for your phone.');
  AddTip('Messages that look like fraud get a red warning, and their links and pictures are switched off so they can''t be clicked by mistake.');
  AddTip('Pick the look you like: Eleonora, Classic Eudora, Thunderbird-style, Lookout classic or new, Gmail-style, or Yahoo-style, in light or dark.');
  AddTip('The Classic Eudora look brings back Eudora 7''s menus, names, and keyboard shortcuts, for everyone who loved the original.');
  AddTip('Calendar, Contacts, and To Do sit beside your mail, and stay in step with Microsoft 365, Google, and CalDAV / CardDAV servers.');
  AddTip('Flag any message as To Do (Ctrl+Shift+G): the task opens the message again with one click, on any computer.');
  AddTip('Send Later waits in the Out mailbox and goes by itself at the time you chose, even if you close Eleonora.');
  AddTip('File > Back Up Eleonora puts your whole setup in one file (with a password if you like), to move it to a new computer: Windows, Mac, or Linux.');
  AddTip('Everything Eleonora does can be scripted: type "eleonora-cli --help" in a command prompt. Programs and plugins only get the permissions you grant them.');
  AddTip('Work Offline keeps everything you do (moves, flags, and replies) and sends it to the servers once you''re back online.');

  Page := WizardForm.InstallingPage;
  Gauge := WizardForm.ProgressGauge;

  TipHeading := TNewStaticText.Create(WizardForm);
  TipHeading.Parent := Page;
  TipHeading.Left := Gauge.Left;
  TipHeading.Top := Gauge.Top + Gauge.Height + ScaleY(28);
  TipHeading.Caption := 'Did you know?';
  TipHeading.Font.Style := [fsBold];

  TipText := TNewStaticText.Create(WizardForm);
  TipText.Parent := Page;
  TipText.ShowAccelChar := False;
  TipText.Left := Gauge.Left;
  TipText.Top := TipHeading.Top + TipHeading.Height + ScaleY(6);
  TipText.AutoSize := False;
  TipText.WordWrap := True;
  TipText.Width := Gauge.Width;
  TipText.Height := ScaleY(64);

  TipCounter := TNewStaticText.Create(WizardForm);
  TipCounter.Parent := Page;
  TipCounter.Left := Gauge.Left;
  TipCounter.Top := TipText.Top + TipText.Height + ScaleY(4);
  TipCounter.Font.Color := clGray;

  TipNext := TNewStaticText.Create(WizardForm);
  TipNext.Parent := Page;
  TipNext.Caption := 'Next tip ›';
  TipNext.Font.Color := clBlue;
  TipNext.Font.Style := [fsUnderline];
  TipNext.Cursor := crHand;
  TipNext.OnClick := @NextTipClick;
  TipNext.Top := TipCounter.Top;
  TipNext.Left := Gauge.Left + Gauge.Width - TipNext.Width;

  ShowTip(0);
  MakeUpgradePage;
  { Eudora 1.x's updater names its own folder (/DIR=…\Eudora): Eleonora goes beside it }
  WizardForm.DirEdit.Text := TargetDir(WizardForm.DirEdit.Text);
end;

procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  if GetTickCount - TipShownAt >= TipSeconds * 1000 then
    ShowTip(CurrentTip + 1);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    ShowTip(0);
  if (CurStep = ssPostInstall) and (WizardIsTaskSelected('addtopath') or OldOnPath) then
    AddToPath(ExpandConstant('{app}'));
  { the version before 1.0.0's desktop shortcut, pointing at eudora27.exe: Eleonora's in its place }
  if (CurStep = ssPostInstall) and ReplacedOld and FileExists(ExpandConstant('{autodesktop}\Eudora.lnk')) then
  begin
    DeleteFile(ExpandConstant('{autodesktop}\Eudora.lnk'));
    if not WizardIsTaskSelected('desktopicon') then
      CreateShellLink(ExpandConstant('{autodesktop}\Eleonora.lnk'), 'Mail for decades of messages', ExpandConstant('{app}\eleonora.exe'), '', ExpandConstant('{app}'), '', 0, SW_SHOWNORMAL);
  end;
  if CurStep = ssPostInstall then
  begin
    FinishEudoraUpgrade;
    { (every install: an Eudora 1.x's file types point at Eleonora, its leftovers go) }
    RemoveEudoraRegistrations;
    RemoveLeftoverEudora;
  end;
end;

{ Deleting the user's data. At the end of uninstalling, when no other Eleonora stays installed
  (that one would still use them) and the uninstall isn't silent, Eleonora asks whether to delete
  this user's mail library, Eleonora's folders (and Eudora's, if Eleonora never took them over),
  and its saved passwords. Keep is the default; Delete
  works only once DELETE is typed. Kept, a reinstall finds everything as it was. }
var
  DeleteButton: TNewButton;
  DeleteWord: TNewEdit;

{ The library remembered in Folder (its last-library.txt: Eleonora's folder, or Eudora's before
  Eleonora first started) when it isn't inside that folder itself, or ''. }
function RememberedLibraryIn(Folder: String): String;
var
  Text: AnsiString;
  Path: String;
begin
  Result := '';
  if not LoadStringFromFile(AddBackslash(Folder) + 'last-library.txt', Text) then exit;
  Path := RemoveBackslashUnlessRoot(Trim(String(Text)));
  { (only a real library, and never a drive's root) }
  if (Length(Path) > 3) and (FileExists(AddBackslash(Path) + 'eleonora.db') or FileExists(AddBackslash(Path) + 'eudora.db'))
    and (Pos(Uppercase(AddBackslash(Folder)), Uppercase(AddBackslash(Path))) <> 1) then
    Result := Path;
end;

procedure DeleteWordChanged(Sender: TObject);
begin
  DeleteButton.Enabled := Trim(DeleteWord.Text) = 'DELETE';
end;

{ Asks; True = delete. Folders: one per line. }
function AskToDelete(Folders: String): Boolean;
var
  Form: TSetupForm;
  Text, Prompt: TNewStaticText;
  KeepButton: TNewButton;
  Gap, Y: Integer;
begin
  Form := CreateCustomForm(ScaleX(520), ScaleY(100), False, False);
  try
    Form.Caption := 'Eleonora Uninstall';
    Gap := ScaleX(12);
    Text := TNewStaticText.Create(Form);
    Text.Parent := Form;
    Text.Left := Gap;
    Text.Top := Gap;
    Text.Width := Form.ClientWidth - 2 * Gap;
    Text.WordWrap := True;
    Text.Caption := 'Eleonora has been removed. Your mail library, accounts, rules, settings, and saved passwords are still on this computer, so installing Eleonora again brings everything back as it was.' + #13#10#13#10 +
      'Do you also want to delete them? This can''t be undone. Mail kept only on this computer (POP3 accounts, imported files, and old Eudora mailboxes) will be gone for good. Mail on Microsoft 365, Gmail, and IMAP servers stays on those servers.' + #13#10#13#10 +
      'These would be deleted:' + #13#10 + Folders +
      '   Eleonora''s saved passwords and sign-ins in Windows Credential Manager';
    Text.AdjustHeight;
    Y := Text.Top + Text.Height + Gap;

    DeleteWord := TNewEdit.Create(Form);
    Prompt := TNewStaticText.Create(Form);
    Prompt.Parent := Form;
    Prompt.Left := Gap;
    Prompt.Top := Y;
    Prompt.Caption := '&To delete them, type DELETE here:';
    Prompt.FocusControl := DeleteWord;
    Y := Y + Prompt.Height + ScaleY(4);

    DeleteWord.Parent := Form;
    DeleteWord.Left := Gap;
    DeleteWord.Top := Y;
    DeleteWord.Width := ScaleX(200);
    DeleteWord.OnChange := @DeleteWordChanged;
    Y := Y + DeleteWord.Height + Gap * 2;

    KeepButton := TNewButton.Create(Form);
    KeepButton.Parent := Form;
    KeepButton.Caption := '&Keep My Data';
    KeepButton.Width := ScaleX(120);
    KeepButton.Height := ScaleY(25);
    KeepButton.Left := Form.ClientWidth - Gap - KeepButton.Width;
    KeepButton.Top := Y;
    KeepButton.ModalResult := mrCancel;
    KeepButton.Default := True;
    KeepButton.Cancel := True;

    DeleteButton := TNewButton.Create(Form);
    DeleteButton.Parent := Form;
    DeleteButton.Caption := '&Delete';
    DeleteButton.Width := ScaleX(120);
    DeleteButton.Height := ScaleY(25);
    DeleteButton.Left := KeepButton.Left - ScaleX(8) - DeleteButton.Width;
    DeleteButton.Top := Y;
    DeleteButton.ModalResult := mrOk;
    DeleteButton.Enabled := False;

    Form.ClientHeight := Y + KeepButton.Height + Gap;
    Form.ActiveControl := KeepButton;
    Result := (Form.ShowModal = mrOk) and (Trim(DeleteWord.Text) = 'DELETE');
  finally
    Form.Free;
  end;
end;

procedure DeleteUserData;
var
  Dirs: array of String;
  List, Left, Folder, Library: String;
  I, Code: Integer;
begin
  { (another Eleonora still installed, for everyone or for this user: it still uses them) }
  if UninstallSilent or RegKeyExists(HKLM, UninstallKey) or RegKeyExists(HKCU, UninstallKey) then exit;
  { Eleonora's folders, and Eudora 1.x's when Eleonora never started to take them over }
  for I := 0 to 3 do
  begin
    case I of
      0: Folder := ExpandConstant('{localappdata}\Eleonora');
      1: Folder := ExpandConstant('{localappdata}\Eudora');
      2: Folder := ExpandConstant('{localappdata}\net.planet.eleonora');
    else
      Folder := ExpandConstant('{localappdata}\net.planet.eudora');
    end;
    if not DirExists(Folder) then continue;
    if I < 2 then
    begin
      Library := RememberedLibraryIn(Folder);
      if Library <> '' then
      begin
        SetArrayLength(Dirs, GetArrayLength(Dirs) + 1);
        Dirs[GetArrayLength(Dirs) - 1] := Library;
      end;
    end;
    SetArrayLength(Dirs, GetArrayLength(Dirs) + 1);
    Dirs[GetArrayLength(Dirs) - 1] := Folder;
  end;
  if GetArrayLength(Dirs) = 0 then exit;
  List := '';
  for I := 0 to GetArrayLength(Dirs) - 1 do
    List := List + '   ' + Dirs[I] + #13#10;
  if not AskToDelete(List) then exit;

  { a download Eleonora (or Eudora) left running would hold the library's files }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM eleonora-cli.exe /IM eleonora.exe /IM eudora-cli.exe /IM eudora.exe /FI "USERNAME eq ' + GetUserNameString + '"', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(1000);
  { saved passwords and sign-ins: Credential Manager entries named "<name>.Eleonora" (and the old "<name>.Eudora", "<name>.Eudora 27") }
  Exec('powershell.exe', '-NoProfile -NonInteractive -Command "cmdkey /list | ForEach-Object { if ($_ -match ''target=(.+\.(Eleonora|Eudora( 27)?))\s*$'') { cmdkey /delete:$($matches[1]) | Out-Null } }"', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Left := '';
  for I := 0 to GetArrayLength(Dirs) - 1 do
  begin
    DelTree(Dirs[I], True, True, True);
    if DirExists(Dirs[I]) then Left := Left + '   ' + Dirs[I] + #13#10;
  end;
  if Left <> '' then
    MsgBox('Some files couldn''t be deleted (another program may be using them). Delete these folders yourself:' + #13#10#13#10 + Left, mbError, MB_OK)
  else
    MsgBox('Your Eleonora mail library, settings, and saved passwords have been deleted from this computer.', mbInformation, MB_OK);
end;

{ Eudora 1.x's file types that Setup pointed at Eleonora (RemoveEudoraRegistrations): removed with
  Eleonora, only when they still open this Eleonora. }
procedure RemoveCarriedOverTypes(Root: Integer);
var
  Kind, Command: String;
  I: Integer;
begin
  for I := 0 to 3 do
  begin
    case I of
      0: Kind := 'eml';
      1: Kind := 'msg';
      2: Kind := 'ics';
    else
      Kind := 'mailto';
    end;
    if RegQueryStringValue(Root, 'Software\Classes\Eudora.' + Kind + '\shell\open\command', '', Command)
      and (Pos(Uppercase(ExpandConstant('{app}\eleonora.exe')), Uppercase(Command)) > 0) then
      RegDeleteKeyIncludingSubkeys(Root, 'Software\Classes\Eudora.' + Kind);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveCarriedOverTypes(HKA);
    if IsAdminInstallMode then RemoveCarriedOverTypes(HKCU);
    RemoveFromPath(ExpandConstant('{app}'));
    DeleteUserData;
  end;
end;
