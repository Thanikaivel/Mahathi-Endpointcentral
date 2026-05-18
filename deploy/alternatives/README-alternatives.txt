UAM Agent — Alternative Deployment Methods
==========================================

Use these in addition to (or instead of) deploy-remote.bat / deploy-remote.ps1.

------------------------------------------------------------------------
1) GROUP POLICY STARTUP SCRIPT  (recommended for domain environments)
------------------------------------------------------------------------
This is the gold standard for AD: machines self-install at next reboot,
and re-installs are blocked by a version marker so it's idempotent.

  Step 1. Copy these files to your SYSVOL Scripts share:
            \\domain.local\sysvol\domain.local\scripts\UAMAgent\
              gpo-startup.bat        (from this folder)
              install.bat            (from ..\bundle\)
              uninstall.bat          (from ..\bundle\)
              uam-agent.exe
              config.json

  Step 2. Open Group Policy Management Console.
          Edit the GPO that's linked to the OU containing your 300 PCs.
          (If you don't have one, create "UAM Agent Deployment".)

  Step 3. Computer Configuration
          -> Policies -> Windows Settings -> Scripts (Startup/Shutdown)
          -> Startup -> Add...
          Script Name: gpo-startup.bat
          (Browse to \\domain.local\sysvol\...\UAMAgent\gpo-startup.bat)

  Step 4. Force replication / re-login or run 'gpupdate /force /target:computer'
          on a couple of clients to test, then reboot one. The agent should
          appear in services.msc as "UAM Activity Agent".

  Logs of the GPO run land in C:\Windows\Temp\uam-gpo-startup.log on each
  client.

------------------------------------------------------------------------
2) WMIC REMOTE LAUNCH  (when PsExec is blocked)
------------------------------------------------------------------------
  Fill in machines.txt (in the parent deploy\ folder), then from an
  elevated CMD on an admin workstation:

        deploy-wmic.bat

  Stages files to \\HOST\C$\Windows\Temp\UAMAgent-Install\ and asks WMI
  to spawn install.bat as SYSTEM.

------------------------------------------------------------------------
3) SCHEDULED-TASK PUSH  (when PsExec AND WMIC are blocked)
------------------------------------------------------------------------
  Same prep, then:

        deploy-schtasks.bat
        REM or with explicit admin creds:
        deploy-schtasks.bat /U CORP\admin /P P@ssw0rd

  Creates a one-shot scheduled task on each host running as SYSTEM,
  triggers it, then removes it.

------------------------------------------------------------------------
4) SELF-EXTRACTING SETUP EXE  (for hand-off / ad-hoc installs)
------------------------------------------------------------------------
  Build a single-file installer (no separate folder copy needed):

        make-self-extractor.bat

  Produces UAM-Agent-Setup.exe in the deploy\ folder. End users (or IT)
  right-click -> Run as administrator. The exe extracts the bundle to
  %TEMP% and runs install.bat for them.

  Uses IExpress, which ships with every modern Windows (no extra tools).

------------------------------------------------------------------------
5) MSI WRAPPER  (if you need Programs & Features visibility / GPO MSI)
------------------------------------------------------------------------
  Easiest path: wrap the bundle with WixToolset (free) or Advanced
  Installer (free for basic projects).

  Minimal Wix XML approach:
    - One <Component> per file in the bundle.
    - One <ServiceInstall> + <ServiceControl> entry to register and start
      the Windows service (replaces install.bat entirely).
    - candle.exe + light.exe to compile to .msi.

  After the .msi exists, deploy via:
    Group Policy: Computer Configuration -> Software Settings ->
                  Software Installation -> New Package, Assigned.
    Or:
        msiexec /i UAMAgent.msi /qn

  Tell me if you want me to write the Wix .wxs file — about 60 lines.

------------------------------------------------------------------------
6) INTUNE / SCCM / CONFIGMGR
------------------------------------------------------------------------
  Take the entire bundle\ folder and wrap it as:
    Intune:  IntuneWinAppUtil.exe -c bundle -s install.bat -o .
             upload the .intunewin to Intune, install command "install.bat",
             uninstall command "uninstall.bat", detection rule = path
             "C:\Program Files\UAMAgent\uam-agent.exe" exists.
    SCCM:    Application -> Deployment Type "Script Installer"
             Install: install.bat
             Uninstall: uninstall.bat
             Detection: C:\Program Files\UAMAgent\uam-agent.exe

------------------------------------------------------------------------
7) RUN-FROM-SHARE (no install on clients)
------------------------------------------------------------------------
  If you'd rather not put binaries on each client, host the bundle on a
  file share and create a Scheduled Task on each client that runs at user
  logon, pointed at \\fileserver\UAMAgent\uam-agent.exe.

  Trade-off: the agent is per-user (not per-machine), so locks/unlocks
  and shutdown handling are weaker. Only worth it if local install is
  truly forbidden by policy.
