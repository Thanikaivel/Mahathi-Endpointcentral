# probe.ps1 - emit a single JSON line describing the current session,
# active user, idle time, foreground application, and (optionally) running apps.
#
# Invoked by the Node agent. Must NEVER print non-JSON to stdout.
#
# Session 0 awareness: when the agent runs as a Windows Service it executes
# in Session 0 (LocalSystem). GetLastInputInfo() is session-scoped and would
# always report 0 idle in that case. We detect Session 0 and use
# WTSQuerySessionInformation(WTSSessionInfoEx) to ask the active console
# session about its LastInputTime instead.

[CmdletBinding()]
param(
    [switch]$IncludeProcesses
)

$ErrorActionPreference = 'SilentlyContinue'

# ---------- Win32 helpers (idle time + foreground window + WTS) ----------
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

    // ----- WTS API for cross-session idle time -----
    [DllImport("Kernel32.dll", SetLastError = true)]
    public static extern uint WTSGetActiveConsoleSessionId();

    [DllImport("Wtsapi32.dll", SetLastError = true)]
    public static extern int WTSQuerySessionInformationW(
        IntPtr hServer,
        uint   sessionId,
        int    wtsInfoClass,
        out IntPtr ppBuffer,
        out uint   pBytesReturned);

    [DllImport("Wtsapi32.dll")]
    public static extern void WTSFreeMemory(IntPtr pMemory);

    // WTS_INFO_CLASS values
    private const int WTSSessionInfoEx = 25;
    private const int WTSIdleTime      = 17;
    private const int WTSUserName      = 5;

    // Returns idle seconds for the calling session.
    public static int GetIdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (GetLastInputInfo(ref lii)) {
            uint t = GetTickCount();
            uint diff = t - lii.dwTime;
            return (int)(diff / 1000u);
        }
        return -1;
    }

    // Returns idle seconds for the *active console session*, queried via WTS.
    // Works correctly when called from Session 0 (services).
    // Returns -1 when no user is signed in or the call failed.
    public static int GetIdleSecondsForActiveSession() {
        string dummy;
        return GetIdleSecondsForActiveSessionDebug(out dummy);
    }

    // Same as above but also produces a JSON-ready debug string explaining
    // what happened — used when the main path returns -1 so we can see why.
    public static int GetIdleSecondsForActiveSessionDebug(out string debugJson) {
        debugJson = "";
        uint sid = WTSGetActiveConsoleSessionId();
        if (sid == 0xFFFFFFFF) {
            debugJson = "{\"step\":\"WTSGetActiveConsoleSessionId\",\"result\":\"no_active_session\"}";
            return -1;
        }

        // ---- Attempt 1: WTSSessionInfoEx (preferred) ----
        IntPtr ppBuf = IntPtr.Zero;
        uint pBytes = 0;
        int ok = WTSQuerySessionInformationW(IntPtr.Zero, sid, WTSSessionInfoEx, out ppBuf, out pBytes);
        int err1 = Marshal.GetLastWin32Error();

        if (ok != 0 && ppBuf != IntPtr.Zero) {
            try {
                // WTSINFOEX:
                //   DWORD Level                offset  0
                //   (4 bytes pad for 8-align)  offset  4
                //   WTSINFOEX_LEVEL1 Data:     offset  8
                //     LastInputTime  at +176
                //     CurrentTime    at +184
                int level = Marshal.ReadInt32(ppBuf, 0);
                long lastInput   = Marshal.ReadInt64(ppBuf, 8 + 176);
                long currentTime = Marshal.ReadInt64(ppBuf, 8 + 184);
                long diffTicks   = currentTime - lastInput;
                long seconds     = (diffTicks > 0) ? diffTicks / 10000000L : 0;

                debugJson = "{\"step\":\"WTSSessionInfoEx\",\"sid\":" + sid +
                            ",\"bytes\":" + pBytes +
                            ",\"level\":" + level +
                            ",\"lastInput\":" + lastInput +
                            ",\"currentTime\":" + currentTime +
                            ",\"idle\":" + seconds + "}";

                if (level == 1 && lastInput > 0 && currentTime > 0) {
                    return (int)seconds;
                }
                // Else fall through to attempt 2.
            } catch (Exception ex) {
                debugJson = "{\"step\":\"WTSSessionInfoEx\",\"exception\":\"" + ex.Message.Replace("\"","'") + "\"}";
            } finally {
                WTSFreeMemory(ppBuf);
            }
        } else {
            debugJson = "{\"step\":\"WTSSessionInfoEx\",\"win32error\":" + err1 + ",\"ok\":" + ok + ",\"sid\":" + sid + "}";
        }

        // ---- Attempt 2: WTSIdleTime (older, returns DWORD seconds directly) ----
        IntPtr p2 = IntPtr.Zero;
        uint b2 = 0;
        int ok2 = WTSQuerySessionInformationW(IntPtr.Zero, sid, WTSIdleTime, out p2, out b2);
        int err2 = Marshal.GetLastWin32Error();
        if (ok2 != 0 && p2 != IntPtr.Zero && b2 >= 4) {
            try {
                int idle = Marshal.ReadInt32(p2, 0);
                debugJson += ";{\"step\":\"WTSIdleTime\",\"idle\":" + idle + ",\"bytes\":" + b2 + "}";
                if (idle >= 0) return idle;
            } catch (Exception ex) {
                debugJson += ";{\"step\":\"WTSIdleTime\",\"exception\":\"" + ex.Message.Replace("\"","'") + "\"}";
            } finally {
                WTSFreeMemory(p2);
            }
        } else {
            debugJson += ";{\"step\":\"WTSIdleTime\",\"win32error\":" + err2 + ",\"ok\":" + ok2 + ",\"bytes\":" + b2 + "}";
        }

        return -1;
    }

    // Returns the active console session id, or -1 if none.
    public static int GetActiveConsoleSessionId() {
        uint sid = WTSGetActiveConsoleSessionId();
        if (sid == 0xFFFFFFFF) return -1;
        return (int)sid;
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

# ---------- Detect whether we are in Session 0 (i.e. running as a service) ----------
$mySessionId = -1
try { $mySessionId = (Get-Process -Id $PID).SessionId } catch { }

# ---------- Active session via WMI ----------
$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$activeUser = $null
$activeDomain = $null
if ($cs -and $cs.UserName) {
    $parts = $cs.UserName.Split('\\')
    if ($parts.Length -eq 2) { $activeDomain = $parts[0]; $activeUser = $parts[1] }
    else { $activeUser = $cs.UserName }
}

# Fallback: Win32_ComputerSystem.UserName is null when called from a service.
# Use 'query session' or WTS to find the active console user.
if (-not $activeUser) {
    try {
        $raw = & query session 2>$null
        if ($raw) {
            foreach ($line in ($raw | Select-Object -Skip 1)) {
                # SESSIONNAME    USERNAME    ID    STATE    TYPE   DEVICE
                # ">console      jdoe        1     Active"
                if ($line -match '^\s*>?\s*console\s+(\S+)\s+\d+\s+Active') {
                    $activeUser = $matches[1]
                    break
                }
            }
        }
    } catch { }
}

# ---------- Locked detection ----------
# When the workstation is locked, LogonUI.exe runs in the user's session.
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

# ---------- Idle seconds (Session 0 aware) ----------
$idleSeconds = 0
$idleSource  = 'none'
$activeConsoleSid = -1
try { $activeConsoleSid = [UamWin32]::GetActiveConsoleSessionId() } catch { }

$wtsDebug = $null
if ($mySessionId -eq 0) {
    # Running as a service - GetLastInputInfo would lie. Use WTS.
    try {
        $dbg = ""
        $w = [UamWin32]::GetIdleSecondsForActiveSessionDebug([ref]$dbg)
        $wtsDebug = $dbg
        if ($w -ge 0) {
            $idleSeconds = [int]$w
            $idleSource  = 'wts'
        } elseif ($locked) {
            $idleSeconds = 0
            $idleSource  = 'locked-fallback'
        } else {
            $idleSeconds = 0
            $idleSource  = 'wts-failed'
        }
    } catch {
        $idleSeconds = 0
        $idleSource  = 'wts-exception'
        $wtsDebug    = $_.Exception.Message
    }
} else {
    # Running interactively - GetLastInputInfo is correct.
    try {
        $i = [UamWin32]::GetIdleSeconds()
        if ($i -ge 0) {
            $idleSeconds = [int]$i
            $idleSource  = 'lastinputinfo'
        }
    } catch { }
}

# ---------- Foreground window (only meaningful in user session) ----------
$fgRaw = "{}"
if ($mySessionId -ne 0) {
    try { $fgRaw = [UamWin32]::GetForegroundInfo() } catch { }
}
# When running as a service we can't see the user's foreground window from
# Session 0 without process-token impersonation tricks. Leave foreground={}.

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
    machineName        = $env:COMPUTERNAME
    domain             = $env:USERDOMAIN
    osCaption          = $osCaption
    osVersion          = $osVersion
    ipAddress          = $ip
    activeUser         = $activeUser
    activeDomain       = $activeDomain
    locked             = $locked
    idleSeconds        = [int]$idleSeconds
    idleSource         = $idleSource
    probeSessionId     = [int]$mySessionId
    activeConsoleId    = [int]$activeConsoleSid
    wtsDebug           = $wtsDebug
    foreground         = ($fgRaw | ConvertFrom-Json)
    sessions           = $sessionStates
    processes          = $processes
    timestampUtc       = [DateTime]::UtcNow.ToString('o')
}

$out | ConvertTo-Json -Depth 5 -Compress
