# UAM Agent installer
# Run as Administrator. PowerShell 5.1+ (Windows PowerShell) is fine.
#
# Quick run (bypassing ExecutionPolicy):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uam-agent.ps1
#
# What this does:
#   1. Extracts uam-agent.zip into C:\ProgramData\UAMAgent.
#   2. Locates nssm.exe (uses bundled local copy first, falls back to download).
#   3. Copies nssm.exe to System32.
#   4. (Re)installs the "uam-agent" Windows service via NSSM.
#   5. Starts the service.

[CmdletBinding()]
param(
    # Where the uam-agent zip is located
    [string]$ZipPath = "C:\ProgramData\UAMAgent\uam-agent.zip",

    # Folder to extract into and where the agent exe will live
    [string]$ExtractPath = "C:\ProgramData\UAMAgent",

    # Name of the agent executable inside (or under) ExtractPath after the zip
    # is unpacked. We search recursively, so a zip that drops everything into
    # a subfolder like 'uam-agent\uam-agent.exe' is fine.
    [string]$ExeName = "uam-agent.exe",

    # Service name shown in services.msc / used by sc.exe
    [string]$ServiceName = "uam-agent",

    # Path to a *local* nssm-2.24.zip you've already shipped to this machine.
    # If empty (default), the script searches several sensible local paths.
    [string]$NssmZipLocal = ""
)

$ErrorActionPreference = 'Stop'

# Resolve the script's own folder reliably (PSScriptRoot can be empty during
# param-block evaluation on some PowerShell hosts; compute it here instead).
$scriptDir = $PSScriptRoot
if (-not $scriptDir -and $MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

# If the user didn't pass -NssmZipLocal, search a few sensible offline locations.
# This is the ONLY way to obtain NSSM - no internet download.
if (-not $NssmZipLocal) {
    $candidates = @(
        (Join-Path $scriptDir   "nssm-2.24.zip"),
        (Join-Path $ExtractPath "nssm-2.24.zip"),
        (Join-Path (Get-Location).Path "nssm-2.24.zip"),
        "C:\ProgramData\UAMAgent\nssm-2.24.zip",
        "C:\packages\nssm-2.24.zip"
    ) | Select-Object -Unique
    foreach ($c in $candidates) {
        if (Test-Path $c) { $NssmZipLocal = $c; break }
    }
}

# ---- Helpers ----------------------------------------------------------------
function Write-Step($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host $msg -ForegroundColor Red }

# Robust unzip using the .NET API. Unlike Expand-Archive -Force, this doesn't
# track previous extractions and doesn't fail if files are locked by a running
# service or were deleted between calls. Each file is overwritten in place.
function Expand-ZipRobust {
    param(
        [Parameter(Mandatory)] [string]$ZipPath,
        [Parameter(Mandatory)] [string]$DestPath
    )
    if (-not (Test-Path $DestPath)) {
        New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            $target = Join-Path $DestPath $entry.FullName
            $targetDir = Split-Path -Parent $target
            if ($targetDir -and -not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            if ($entry.Name) {
                # Real file (Name is empty for directory-only entries)
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true) | Out-Null
            }
        }
    } finally {
        $zip.Dispose()
    }
}

# Stop an existing UAM service if present so the zip extract isn't
# blocked by file-in-use locks on the running binary or its support files.
function Stop-UAMServiceIfPresent {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Step "No existing '$Name' service found - fresh install."
        return $false
    }

    Write-Warn "Detected existing '$Name' service (status: $($svc.Status))."
    Write-Step "Stopping it before upgrading to the latest files ..."
    try {
        if ((Get-Command nssm -ErrorAction SilentlyContinue)) {
            & nssm stop $Name confirm 2>$null | Out-Null
        }
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    } catch { }
    # Wait up to 15s for the process to actually release file handles
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $svc.Refresh()
        if ($svc.Status -eq 'Stopped') { break }
    }
    if ($svc.Status -eq 'Stopped') {
        Write-OK "Service stopped - file locks released."
    } else {
        Write-Warn "Service did not reach STOPPED in 15s (current: $($svc.Status)). Continuing anyway."
    }
    return $true
}

# Stop, kill orphan processes, and *delete* an existing UAM service.
# Tries NSSM first, then sc.exe - works even if NSSM was removed/upgraded.
function Remove-UAMServiceClean {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$ExeBaseName = "uam-agent"   # process name to kill if orphaned
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Step "Removing existing service '$Name' ..."
        # 1. Stop
        try {
            if (Get-Command nssm -ErrorAction SilentlyContinue) {
                & nssm stop $Name confirm 2>$null | Out-Null
            }
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        } catch { }
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 1
            $svc.Refresh()
            if ($svc.Status -eq 'Stopped') { break }
        }

        # 2. Kill any leftover processes still holding files
        Get-Process -Name $ExeBaseName -ErrorAction SilentlyContinue |
            ForEach-Object {
                Write-Warn "Killing orphan process $($_.Id) ($($_.ProcessName))"
                try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch { }
            }

        # 3. Delete the service registration. Try nssm first, then sc.exe.
        $deleted = $false
        if (Get-Command nssm -ErrorAction SilentlyContinue) {
            $r = & nssm remove $Name confirm 2>&1
            if ($LASTEXITCODE -eq 0) { $deleted = $true }
        }
        if (-not $deleted) {
            & sc.exe delete $Name | Out-Null
        }

        # 4. Wait for the SCM to actually drop it
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Seconds 1
            if (-not (Get-Service -Name $Name -ErrorAction SilentlyContinue)) { break }
        }
        if (Get-Service -Name $Name -ErrorAction SilentlyContinue) {
            Write-Warn "Service '$Name' is still registered; SCM may need a reboot to fully release it."
        } else {
            Write-OK "Service '$Name' removed."
        }
    }
}

# ---- 0. Elevation check -----------------------------------------------------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "This script must be run as Administrator."
    exit 1
}

# ---- 1. Sanity checks -------------------------------------------------------
if (-not (Test-Path $ZipPath)) {
    Write-Err "uam-agent.zip not found at: $ZipPath"
    Write-Err "Copy the zip there first, or pass -ZipPath."
    exit 2
}
New-Item -ItemType Directory -Force -Path $ExtractPath | Out-Null

# ---- 2. Stop existing service so files aren't locked, then extract ----------
[void](Stop-UAMServiceIfPresent -Name $ServiceName)

Write-Step "Extracting UAM Agent from $ZipPath ..."
Expand-ZipRobust -ZipPath $ZipPath -DestPath $ExtractPath

# Search recursively for the named exe - the zip may extract straight into
# ExtractPath, or into a subfolder of it.
$found = Get-ChildItem -Path $ExtractPath -Recurse -Filter $ExeName -File -ErrorAction SilentlyContinue |
         Select-Object -First 1

if (-not $found) {
    Write-Err "$ExeName not found anywhere under $ExtractPath after extraction."
    Write-Err ""
    Write-Err "Files actually extracted:"
    Get-ChildItem -Path $ExtractPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.exe', '.cmd', '.bat', '.js' } |
        Select-Object -First 25 |
        ForEach-Object { Write-Host "    $($_.FullName)" }
    Write-Err ""
    Write-Err "If your binary is named differently, re-run with:"
    Write-Err "    -ExeName <your-binary-name.exe>"
    exit 3
}
$exePath  = $found.FullName
$exeDir   = Split-Path -Parent $exePath
Write-OK "Found agent at: $exePath"

# ---- 3. Resolve NSSM (prefer raw nssm.exe; fall back to nssm-2.24.zip) ------
$arch        = if ([Environment]::Is64BitOperatingSystem) { 'win64' } else { 'win32' }
$nssmExtract = Join-Path $ExtractPath "nssm"
$nssmCandidate = $null

# 3a. Look for a raw nssm.exe - by far the simplest deploy:
#     just drop nssm.exe next to the script (no zip, no unpacking).
$rawCandidates = @(
    (Join-Path $scriptDir   "nssm.exe"),
    (Join-Path $ExtractPath "nssm.exe"),
    (Join-Path (Get-Location).Path "nssm.exe"),
    "C:\ProgramData\UAMAgent\nssm.exe",
    "C:\packages\nssm.exe"
) | Select-Object -Unique

foreach ($p in $rawCandidates) {
    if (Test-Path $p) {
        Write-Step "Using local NSSM exe: $p"
        $nssmCandidate = Get-Item $p
        break
    }
}

# 3b. Fall back to nssm-2.24.zip (if the user shipped the zip instead of the exe).
if (-not $nssmCandidate) {
    if ($NssmZipLocal -and (Test-Path $NssmZipLocal)) {
        Write-Step "Using local NSSM zip:  $NssmZipLocal"
        $nssmZip = Join-Path $ExtractPath "nssm.zip"
        Copy-Item -LiteralPath $NssmZipLocal -Destination $nssmZip -Force

        if (Test-Path $nssmExtract) {
            try { Remove-Item -Recurse -Force $nssmExtract -ErrorAction SilentlyContinue } catch { }
        }
        Expand-ZipRobust -ZipPath $nssmZip -DestPath $nssmExtract

        $nssmCandidate = Get-ChildItem -Path $nssmExtract -Recurse -Filter 'nssm.exe' |
                         Where-Object { $_.FullName -like "*\$arch\*" } |
                         Select-Object -First 1
    }
}

if (-not $nssmCandidate) {
    Write-Err "NSSM not found locally. This installer is OFFLINE-ONLY by design."
    Write-Err ""
    Write-Err "Easiest fix: place a copy of nssm.exe in any of these folders:"
    foreach ($p in $rawCandidates) { Write-Err "    $p" }
    Write-Err ""
    Write-Err "Or place the full nssm-2.24.zip in one of:"
    Write-Err "    $scriptDir\nssm-2.24.zip"
    Write-Err "    C:\ProgramData\UAMAgent\nssm-2.24.zip"
    Write-Err "    C:\packages\nssm-2.24.zip"
    Write-Err ""
    Write-Err "Or pass the explicit path:"
    Write-Err "    -NssmZipLocal D:\path\to\nssm-2.24.zip"
    Write-Err ""
    Write-Err "How to obtain nssm.exe (download once on a machine that has internet):"
    Write-Err "    1. https://nssm.cc/release/nssm-2.24.zip"
    Write-Err "    2. Unzip; inside the win64\ folder you'll find nssm.exe (~360 KB)."
    Write-Err "    3. Copy ONLY nssm.exe to your offline clients."
    exit 5
}

$nssmTarget = "C:\Windows\System32\nssm.exe"
Copy-Item $nssmCandidate.FullName $nssmTarget -Force
Write-OK "Installed: $nssmTarget  ($arch)"

# ---- 5. (Re)install service -------------------------------------------------
# Always remove the prior service registration cleanly before re-creating -
# this is the upgrade path. Safe no-op if the service doesn't exist yet.
Remove-UAMServiceClean -Name $ServiceName -ExeBaseName ([System.IO.Path]::GetFileNameWithoutExtension($ExeName))

Write-Step "Installing fresh '$ServiceName' service ..."
& nssm install $ServiceName $exePath               | Out-Null
& nssm set $ServiceName DisplayName "UAM Agent"    | Out-Null
& nssm set $ServiceName Description "UAM Agent Monitoring Service" | Out-Null
& nssm set $ServiceName Start SERVICE_AUTO_START   | Out-Null
& nssm set $ServiceName AppDirectory $exeDir       | Out-Null
& nssm set $ServiceName AppStdout "$exeDir\uam-agent.out.log" | Out-Null
& nssm set $ServiceName AppStderr "$exeDir\uam-agent.err.log" | Out-Null
# Restart on failure: 60s delay, throttle 1500 ms
& nssm set $ServiceName AppExit Default Restart    | Out-Null
& nssm set $ServiceName AppRestartDelay 60000      | Out-Null
& nssm set $ServiceName AppThrottle 1500           | Out-Null

Write-OK "Service '$ServiceName' configured."

# ---- 6. Start ---------------------------------------------------------------
Write-Step "Starting '$ServiceName' ..."
& nssm start $ServiceName | Out-Null
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "Service status:" -ForegroundColor Yellow
& nssm status $ServiceName

Write-Host ""
Write-OK "Done. Logs: $exeDir\uam-agent.out.log / uam-agent.err.log"
