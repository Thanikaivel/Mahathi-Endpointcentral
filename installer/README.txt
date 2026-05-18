UAM Activity Agent - MSI Installer
====================================

This folder builds a proper Windows Installer (MSI) package for the UAM Agent.
Why MSI:
  - Defender does not flag MSI files the way it flags custom .exe installers.
  - Shows up in "Programs and Features" / "Installed apps".
  - Native upgrade, downgrade, and uninstall semantics.
  - Deployable via Group Policy Software Installation, Intune, SCCM, msiexec.
  - The agent itself runs as Node.js source files (no pkg-built exe to fight).

ONE-TIME PREP on the build machine
----------------------------------
1. Install WiX Toolset 3.14 (free):
       https://wixtoolset.org/releases/
   This adds candle.exe / light.exe / heat.exe to your PATH.

2. Install Node.js LTS (build needs npm):
       https://nodejs.org/

3. Download WinSW (signed Windows service wrapper):
       https://github.com/winsw/winsw/releases
   Get  WinSW-x64.exe  and save it as:
       installer\staging\winsw\uam-agent-service.exe
   (Renaming is required - WinSW reads <id>-service.xml next to itself.)

4. (Optional) drop an icon at  installer\staging\uam.ico .

BUILDING THE MSI
----------------
    cd installer
    build-msi.bat

Output:  installer\out\UAMAgent.msi   (~25 MB)

The build script:
  - Stages a clean copy of client-agent\ into staging\agent\.
  - Runs npm install --omit=dev there to bake production node_modules.
  - heat.exe harvests every file under staging\agent\ into a ComponentGroup.
  - candle.exe + light.exe compile the .wxs into UAMAgent.msi.
  - Optionally signs with signtool if SIGN_CERT_PFX is set.

INSTALLING ON A CLIENT
----------------------
    msiexec /i UAMAgent.msi /qn /l*v install.log

  /qn   = quiet, no UI
  /l*v  = verbose log to install.log (helpful for debugging)

Prerequisite on the client: Node.js LTS must already be installed
(the MSI's LaunchCondition checks HKLM\SOFTWARE\Node.js).

UNINSTALL
---------
    msiexec /x UAMAgent.msi /qn

or "Programs and Features" -> UAM Activity Agent -> Uninstall.

DEPLOYING TO 300 MACHINES
-------------------------
Option A - Group Policy Software Installation:
  1. Copy UAMAgent.msi to \\domain.local\sysvol\domain.local\scripts\
  2. GPMC -> Computer Configuration -> Policies -> Software Settings ->
     Software installation -> New -> Package...
     Path: \\domain.local\sysvol\domain.local\scripts\UAMAgent.msi
     Method: Assigned
  3. Scope the GPO to the OU containing your client machines.
  4. Reboot the clients (or wait); GPO installs the MSI at next boot.

  CAVEAT: GPO Software Installation will fail if Node.js isn't already on
  the target. Either deploy Node.js LTS via the same GPO first, or build
  a Burn bundle (next option) that chains the two.

Option B - Intune Win32 app:
  IntuneWinAppUtil.exe -c installer\out -s UAMAgent.msi -o installer\out
  Upload .intunewin.
  Install command:    msiexec /i UAMAgent.msi /qn
  Uninstall command:  msiexec /x {b3a7e2f4-9c4d-4e5b-8f2a-1d2c3b4a5e6f} /qn
  Detection rule:     MSI ProductCode  {b3a7e2f4-9c4d-4e5b-8f2a-1d2c3b4a5e6f}

Option C - SCCM/MECM:
  Application -> Deployment Type "Windows Installer (.msi)"
  Detection rule: MSI ProductCode (auto-populated from the file).

Option D - msiexec push (PsExec, WMIC, etc.):
  Same as the .bat-based push, but the install command is just:
       msiexec /i \\share\UAMAgent.msi /qn

UPGRADING
---------
The Product element's Id="*" auto-generates a new ProductCode for each build.
The MajorUpgrade element handles upgrades automatically:
  - Bump  Version="1.0.0"  in UAMAgent.wxs.
  - Rebuild MSI.
  - Deploy. The new MSI uninstalls the old version and installs the new one
    in one step.

To downgrade in an emergency, you'll need to uninstall first.

WHAT THE MSI INSTALLS
---------------------
  C:\Program Files\UAMAgent\
      package.json
      config.json
      uam-agent-service.exe       (WinSW, signed)
      uam-agent-service.xml       (WinSW config)
      src\
      node_modules\
  C:\ProgramData\UAMAgent\
      spool\
      uam-agent-service.out.log   (WinSW captures stdout)
      uam-agent-service.err.log
      agent.log                   (the agent's own log)
  Windows Service "UAM Activity Agent" (LocalSystem, autostart, restart-on-fail)

CHANGING THE CONFIG
-------------------
config.json sits at  C:\Program Files\UAMAgent\config.json  after install.
Edit it (must be admin) and  net stop "UAM Activity Agent" & net start "UAM Activity Agent".

Or, for fleet-wide config changes, rebuild the MSI with the new config.json
and redeploy - the upgrade replaces the file.

CODE-SIGNING THE MSI (recommended)
----------------------------------
If you have a code-signing cert:
    set SIGN_CERT_PFX=C:\certs\code-signing.pfx
    set SIGN_CERT_PASS=YourPfxPassword
    build-msi.bat

The MSI is signed in addition to the embedded WinSW exe (which is
already signed by Cloudbees).

TROUBLESHOOTING
---------------
- "Node.js 18 LTS or later is required" -> Install Node.js MSI first, retry.
- Service stuck in "Starting" -> Check  C:\ProgramData\UAMAgent\uam-agent-service.err.log
  Most common cause: config.json missing or apiBaseUrl unreachable.
- Service crashes on start, restarts in a loop -> Look at agent.log for the actual error.
- Need verbose install logging:
      msiexec /i UAMAgent.msi /l*v %temp%\uam-msi.log
