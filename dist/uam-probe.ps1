# probe.ps1 - emit a single JSON line describing the current session,
# active user, idle time, foreground application, and (optionally) running apps.
#
# Invoked by the Node agent. Must NEVER print non-JSON to stdout.

[CmdletBinding()]
param(
    [switch]$IncludeProcesses
)

$ErrorActionPreference = 'SilentlyContinue'

# ---------- Win32 helpers (idle time + foreground window) ----------
$signature = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public class UamWin32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll")]
    public static extern uint GetTickCount();

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    public static uint GetIdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (GetLastInputInfo(ref lii)) {
            uint t = GetTickCount();
            uint diff = t - lii.dwTime;
            return diff / 1000u;
        }
        return 0u;
    }

    public static string GetForegroundInfo() {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return "{}";
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(h, sb, sb.Capacity);
        uint pid = 0;
        GetWindowThreadProcessId(h, out pid);
        string title = sb.ToString().Replace("\\", "\\\\").Replace("\"", "\\\"");
        string name = "";
        string fpath = "";
        try {
            Process p = Process.GetProcessById((int)pid);
            name = p.ProcessName;
            try { fpath = p.MainModule.FileName.Replace("\\", "\\\\").Replace("\"", "\\\""); } catch { }
        } catch { }
        return "{\"pid\":" + pid + ",\"name\":\"" + name + "\",\"path\":\"" + fpath + "\",\"title\":\"" + title + "\"}";
    }
}
'@
Add-Type -TypeDefinition $signature -ReferencedAssemblies "System.Diagnostics.Process" -ErrorAction SilentlyContinue

# ---------- Active session via WMI ----------
$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$activeUser = $null
$activeDomain = $null
if ($cs -and $cs.UserName) {
    $parts = $cs.UserName.Split('\\')
    if ($parts.Length -eq 2) { $activeDomain = $parts[0]; $activeUser = $parts[1] }
    else { $activeUser = $cs.UserName }
}

# ---------- Locked detection ----------
# When the workstation is locked, LogonUI.exe runs.
$locked = $false
if (Get-Process -Name LogonUI -ErrorAction SilentlyContinue) { $locked = $true }

# ---------- Session state via 'query session' ----------
$sessionStates = @{}
try {
    $raw = & query session 2>$null
    if ($raw) {
        foreach ($line in ($raw | Select-Object -Skip 1)) {
            if ($line -match '^\s*[>]?\s*(\S+)\s+(\S*)\s+(\d+)\s+(\S+)') {
                $sessionStates[$matches[1]] = @{ user = $matches[2]; id = $matches[3]; state = $matches[4] }
            }
        }
    }
} catch { }

# ---------- IP & OS ----------
$ip = $null
try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -ne '127.0.0.1' } |
           Select-Object -First 1).IPAddress
} catch { }
if (-not $ip) {
    try { $ip = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1 -ErrorAction SilentlyContinue).IPv4Address.IPAddressToString } catch { }
}

$osCaption = $null; $osVersion = $null
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) { $osCaption = $os.Caption; $osVersion = $os.Version }
} catch { }

$idleSeconds = 0
try { $idleSeconds = [UamWin32]::GetIdleSeconds() } catch { }

$fgRaw = "{}"
try { $fgRaw = [UamWin32]::GetForegroundInfo() } catch { }

# ---------- Optional: running processes ----------
$processes = @()
if ($IncludeProcesses) {
    try {
        $processes = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -and $_.SessionId -ne 0 } |
            Group-Object -Property ProcessName |
            ForEach-Object {
                $first = $_.Group | Select-Object -First 1
                $fpath = ""
                try { $fpath = $first.MainModule.FileName } catch { }
                @{
                    name  = $_.Name
                    path  = $fpath
                    count = $_.Count
                }
            }
    } catch { }
}

# ---------- Output JSON ----------
$out = [ordered]@{
    machineName     = $env:COMPUTERNAME
    domain          = $env:USERDOMAIN
    osCaption       = $osCaption
    osVersion       = $osVersion
    ipAddress       = $ip
    activeUser      = $activeUser
    activeDomain    = $activeDomain
    locked          = $locked
    idleSeconds     = [int]$idleSeconds
    foreground      = ($fgRaw | ConvertFrom-Json)
    sessions        = $sessionStates
    processes       = $processes
    timestampUtc    = [DateTime]::UtcNow.ToString('o')
}

$out | ConvertTo-Json -Depth 5 -Compress
