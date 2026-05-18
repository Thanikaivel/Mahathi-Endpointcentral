<#
.SYNOPSIS
   Push the UAM Activity Agent install bundle to every machine in machines.txt
   using PowerShell remoting.

.PREREQUISITES
   - PSRemoting enabled on targets (Enable-PSRemoting -Force).
   - You're running as a user with local-admin rights on every target,
     OR you pass -Credential.
   - bundle\uam-agent.exe and bundle\config.json exist next to this script.

.USAGE
   .\deploy-remote.ps1
   .\deploy-remote.ps1 -Credential (Get-Credential)
   .\deploy-remote.ps1 -ThrottleLimit 20
#>
[CmdletBinding()]
param(
  [pscredential]$Credential,
  [int]$ThrottleLimit = 16
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$bundle  = Join-Path $root 'bundle'
$listTxt = Join-Path $root 'machines.txt'
$remoteDir = 'C:\Windows\Temp\UAMAgent-Install'

foreach ($f in 'uam-agent.exe','config.json','install.bat','uninstall.bat') {
  if (-not (Test-Path (Join-Path $bundle $f))) {
    throw "Missing $f in $bundle. Build the agent and run again."
  }
}
if (-not (Test-Path $listTxt)) { throw "machines.txt not found in $root" }

$hosts = Get-Content $listTxt |
         ForEach-Object { $_.Trim() } |
         Where-Object   { $_ -and -not $_.StartsWith('#') }

if (-not $hosts) { throw "machines.txt is empty after stripping comments." }

Write-Host "Targets: $($hosts.Count)"
Write-Host "Bundle:  $bundle"
Write-Host ""

$sessionParams = @{ ComputerName = $hosts; ThrottleLimit = $ThrottleLimit }
if ($Credential) { $sessionParams['Credential'] = $Credential }

$sessions = New-PSSession @sessionParams

try {
  # 1. Ensure remote dir
  Invoke-Command -Session $sessions -ScriptBlock {
    param($d)
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  } -ArgumentList $remoteDir

  # 2. Copy bundle
  Write-Host "Copying bundle to all targets..."
  foreach ($f in Get-ChildItem $bundle -File) {
    Copy-Item -Path $f.FullName -Destination $remoteDir -ToSession $sessions -Force
  }

  # 3. Run install.bat
  Write-Host "Running install.bat on all targets..."
  $results = Invoke-Command -Session $sessions -ScriptBlock {
    param($d)
    $log = & cmd /c "$d\install.bat" 2>&1 | Out-String
    [pscustomobject]@{
      Host    = $env:COMPUTERNAME
      Code    = $LASTEXITCODE
      Output  = $log.Trim()
    }
  } -ArgumentList $remoteDir

  $ok = ($results | Where-Object Code -eq 0).Count
  $bad = ($results | Where-Object Code -ne 0)

  Write-Host ""
  Write-Host "============================================================"
  Write-Host "Success: $ok    Failed: $($bad.Count) of $($hosts.Count)"
  Write-Host "============================================================"

  if ($bad.Count -gt 0) {
    Write-Host ""
    Write-Host "Failures:" -ForegroundColor Yellow
    $bad | ForEach-Object {
      Write-Host "--- $($_.Host)  (exit $($_.Code)) ---" -ForegroundColor Yellow
      Write-Host $_.Output
    }
  }
} finally {
  Remove-PSSession $sessions -ErrorAction SilentlyContinue
}
