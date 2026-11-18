# Puts the Eleonora just built into a fixed place to run and pin (%LOCALAPPDATA%\Programs\Eleonora),
# with a Start Menu shortcut "Eleonora" that opens the library; then starts it again.
#
# Why (2026-10-21): the taskbar showed a generic icon after builds. Running the build's own
# target\release program, Windows read its icon while a build was rewriting it. Now a build
# never touches the copy that runs, and the copy is replaced in one step (a running program can be
# renamed, never overwritten), so it's never missing or half-written. Builds no longer wait for
# Eleonora to close either.
#
#   .\scripts\install-dev.ps1                      # copy, shortcut, restart Eleonora on its library
#   .\scripts\install-dev.ps1 -Library D:\Other    # the shortcut names this library
#   .\scripts\install-dev.ps1 -NoStart             # copy only
#
# Without -Library the shortcut names none, so Eleonora opens the library it remembers (the last
# one opened by name, or restored: 2026-10-27, a shortcut naming C:\EudoraTest\library overrode a
# restore), else the usual place, as the installer's shortcut does.
#
# Before 1.0.0 the window was eudora27.exe in Programs\Eudora 27; in 1.x it was eudora.exe (and the
# command line eudora-cli.exe) in Programs\Eudora; from 2.0.0 they're eleonora.exe and
# eleonora-cli.exe in Programs\Eleonora. The old folders and their registrations are removed here,
# as the installer does.
#
# Never inside another app's container: run from a packaged app, Windows quietly redirects every
# write to %LOCALAPPDATA% into that app's own private copy, and the Eleonora it starts would use a
# library nobody else sees. So when this script finds itself in a package's context it starts
# itself again outside (through Windows' management service, in the user's own session), waits,
# and shows what that run printed.
param(
    [string]$Library = '',
    [switch]$NoStart,
    [string]$OutsideLog = ''
)
$ErrorActionPreference = 'Stop'

# (a probe file: Windows' own "am I in a package" answer can say no while writes are redirected;
# a redirected file lands in that app's LocalCache, where it shows)
$probe = "eleonora-redirect-probe-$PID.tmp"
Set-Content (Join-Path $env:LOCALAPPDATA $probe) 'x'
$redirected = [bool](Get-ChildItem (Join-Path $env:LOCALAPPDATA "Packages\*\LocalCache\Local\$probe") -ErrorAction SilentlyContinue)
Remove-Item (Join-Path $env:LOCALAPPDATA $probe) -ErrorAction SilentlyContinue
if ($redirected) {
    $log = Join-Path (Split-Path $PSScriptRoot) 'target\install-dev-outside.log'
    Remove-Item $log -ErrorAction SilentlyContinue
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -OutsideLog `"$log`""
    if ($Library) { $arguments += " -Library `"$Library`"" }
    if ($NoStart) { $arguments += ' -NoStart' }
    Write-Output 'Running inside another app''s container (its AppData is redirected): installing from outside it instead.'
    $started = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "powershell $arguments" }
    if ($started.ReturnValue -ne 0) { throw "Couldn't start the install outside the container (Windows answered $($started.ReturnValue))." }
    $deadline = (Get-Date).AddMinutes(3)
    while (-not ((Test-Path $log) -and ((Get-Content $log -Raw) -match '(?m)^(END|FAILED)'))) {
        if ((Get-Date) -gt $deadline) { throw "The install outside the container didn't finish within 3 minutes (see $log)." }
        Start-Sleep -Milliseconds 500
    }
    $text = Get-Content $log
    $text | Where-Object { $_ -notmatch '^(END|FAILED)' } | Write-Output
    if ($text -match '^FAILED') { throw ($text | Where-Object { $_ -match '^FAILED' } | Select-Object -First 1) }
    return
}
if ($OutsideLog) {
    Start-Transcript -Path "$OutsideLog.transcript" -Force | Out-Null
    trap { "FAILED: $_" | Add-Content $OutsideLog; Stop-Transcript | Out-Null; exit 1 }
}
function Say($text) { Write-Output $text; if ($OutsideLog) { $text | Add-Content $OutsideLog } }

$build = Join-Path (Split-Path $PSScriptRoot) 'target\release'
$dest = Join-Path $env:LOCALAPPDATA 'Programs\Eleonora'
# the folders of the versions before: "Eudora 27" before 1.0.0, "Eudora" in 1.x
$oldDests = @((Join-Path $env:LOCALAPPDATA 'Programs\Eudora 27'), (Join-Path $env:LOCALAPPDATA 'Programs\Eudora'))
New-Item -ItemType Directory -Force $dest | Out-Null

foreach ($name in 'eleonora.exe', 'eleonora-cli.exe') {
    $from = Join-Path $build $name
    if (-not (Test-Path $from)) { throw "$from isn't built yet (cargo build --release -p eleonora-app -p eleonora-cli)" }
    $to = Join-Path $dest $name
    # the new copy written in full first, then put in place by renaming
    Copy-Item $from "$to.new" -Force
    if (Test-Path $to) { Move-Item $to "$to.$(Get-Date -Format yyyyMMdd-HHmmss).old" }
    Move-Item "$to.new" $to
}
# old copies still running are left until they stop
Get-ChildItem $dest -Filter '*.old' | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

# the Start Menu shortcut (pin this one: it names the library)
$exe = Join-Path $dest 'eleonora.exe'
$programs = [Environment]::GetFolderPath('Programs')
$link = Join-Path $programs 'Eleonora.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($link)
$shortcut.TargetPath = $exe
$shortcut.Arguments = if ($Library) { "`"$Library`"" } else { '' }
$shortcut.WorkingDirectory = $dest
$shortcut.IconLocation = "$exe,0"
$shortcut.Description = 'Eleonora'
$shortcut.Save()
# (the shortcut was "Eudora 27" before 2026-10-25 and "Eudora" in 1.x: those go)
foreach ($old in 'Eudora 27.lnk', 'Eudora.lnk') {
    $old = Join-Path $programs $old
    if (Test-Path $old) { Remove-Item $old -Force }
}
Say "Installed in $dest; Start Menu shortcut: $link"

# .eml, .msg (in the message viewer), and .ics open with Eleonora (as the installer registers
# them, for this user): listed under Open with and in Windows' Default apps, where the user picks
# it once
$classes = 'HKCU:\Software\Classes'
function Set-Value($key, $name, $value) {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    if ($name -eq '') { Set-Item -Path $key -Value $value } else { New-ItemProperty -Path $key -Name $name -Value $value -PropertyType String -Force | Out-Null }
}
function Remove-Key($key) { if (Test-Path $key) { Remove-Item $key -Recurse -Force } }
# the old programs' own entries: eudora27.exe before 1.0.0; Eudora 1.x's (only when its own key is
# there: classic Eudora 7 may own Clients\Mail\Eudora and Applications\eudora.exe)
Remove-Key "$classes\Applications\eudora27.exe"
if (Test-Path 'HKCU:\Software\Planet Networks\Eudora') {
    # (its file types kept and opened with Eleonora, as the installer does: Windows keeps the
    # user's default program by that name, Eudora.msg, and lets no program change the choice)
    foreach ($kind in 'eml', 'msg', 'ics', 'mailto') {
        if (Test-Path "$classes\Eudora.$kind") {
            Set-Value "$classes\Eudora.$kind\DefaultIcon" '' "$exe,0"
            Set-Value "$classes\Eudora.$kind\shell\open\command" '' "`"$exe`" `"%1`""
        }
        if ($kind -ne 'mailto') { Remove-ItemProperty "$classes\.$kind\OpenWithProgids" -Name "Eudora.$kind" -ErrorAction SilentlyContinue }
    }
    Remove-Key "$classes\Applications\eudora.exe"
    Remove-Key 'HKCU:\Software\Clients\Mail\Eudora'
    Remove-ItemProperty 'HKCU:\Software\RegisteredApplications' -Name 'Eudora' -ErrorAction SilentlyContinue
    Remove-Key 'HKCU:\Software\Planet Networks\Eudora'
}
foreach ($kind in @(@{ Ext = '.eml'; Name = 'Email message' }, @{ Ext = '.msg'; Name = 'Outlook message' }, @{ Ext = '.ics'; Name = 'Calendar file' }, @{ Ext = '.vcf'; Name = 'Contact card' })) {
    $progId = 'Eleonora' + $kind.Ext
    Set-Value "$classes\$progId" '' $kind.Name
    Set-Value "$classes\$progId\DefaultIcon" '' "$exe,0"
    Set-Value "$classes\$progId\shell\open\command" '' "`"$exe`" `"%1`""
    Set-Value "$classes\$($kind.Ext)\OpenWithProgids" $progId ''
    Set-Value "$classes\Applications\eleonora.exe\SupportedTypes" $kind.Ext ''
    Set-Value 'HKCU:\Software\Planet Networks\Eleonora\Capabilities\FileAssociations' $kind.Ext $progId
}
# mailto: links: offered in
# Default apps as the mail program; Windows lets the user choose it there
Set-Value "$classes\Eleonora.mailto" '' 'URL:MailTo Protocol'
Set-Value "$classes\Eleonora.mailto" 'URL Protocol' ''
Set-Value "$classes\Eleonora.mailto\DefaultIcon" '' "$exe,0"
Set-Value "$classes\Eleonora.mailto\shell\open\command" '' "`"$exe`" `"%1`""
Set-Value 'HKCU:\Software\Planet Networks\Eleonora\Capabilities\URLAssociations' 'mailto' 'Eleonora.mailto'
Set-Value 'HKCU:\Software\Clients\Mail\Eleonora' '' 'Eleonora'
Set-Value 'HKCU:\Software\Clients\Mail\Eleonora\Capabilities' 'ApplicationName' 'Eleonora'
Set-Value 'HKCU:\Software\Clients\Mail\Eleonora\Capabilities\URLAssociations' 'mailto' 'Eleonora.mailto'
Set-Value 'HKCU:\Software\Planet Networks\Eleonora\Capabilities' 'ApplicationName' 'Eleonora'
Set-Value 'HKCU:\Software\Planet Networks\Eleonora\Capabilities' 'ApplicationDescription' 'Mail for decades of messages'
Set-Value 'HKCU:\Software\RegisteredApplications' 'Eleonora' 'Software\Planet Networks\Eleonora\Capabilities'
# (the name Open with shows, and Explorer told the associations changed, as the installer's
# ChangesAssociations does: without it, Open with didn't list Eudora for .msg until a sign-out)
Set-Value "$classes\Applications\eleonora.exe" 'FriendlyAppName' 'Eleonora'
Set-Value "$classes\Applications\eleonora.exe\shell\open\command" '' "`"$exe`" `"%1`""
Add-Type -Namespace Eleonora -Name Shell -MemberDefinition '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr a, System.IntPtr b);'
[Eleonora.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

if (-not $NoStart) {
    # the window (eleonora.exe; eudora.exe in 1.x, eudora27.exe before 1.0.0), and its background
    # download, which stopping the window this way leaves running: the library's own copy of the
    # command line in <library>\bin (eleonora-cli.exe; eudora-cli.exe in 1.x, eudora.exe before
    # 1.0.0). The window starts the new one within 30 s, and it resumes where it was.
    Get-Process eudora27 -ErrorAction SilentlyContinue | Stop-Process
    Get-Process eleonora -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Stop-Process
    Get-Process eudora -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Programs\Eudora\eudora.exe' -or $_.Path -like '*\bin\eudora.exe' } | Stop-Process
    Get-Process eleonora-cli, eudora-cli -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\bin\*-cli.exe' } | Stop-Process
    Start-Sleep -Seconds 2
}
# the old program folders, once nothing runs from them
foreach ($oldDest in $oldDests) {
    if (-not (Test-Path $oldDest)) { continue }
    Remove-Item $oldDest -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $oldDest) { Say "Couldn't remove $oldDest yet (something still runs from it): it goes next time." }
    else { Say "Removed the old program folder $oldDest" }
}
if (-not $NoStart) {
    if ($Library) { Start-Process $exe -ArgumentList "`"$Library`"" -WorkingDirectory $dest } else { Start-Process $exe -WorkingDirectory $dest }
    Start-Sleep -Seconds 6
    $running = Get-Process eleonora -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
    if ($running) { Say "Eleonora is running from $exe (process $($running.Id -join ', '))." } else { throw 'Eleonora did not start.' }
}
if ($OutsideLog) { 'END' | Add-Content $OutsideLog; Stop-Transcript | Out-Null }
