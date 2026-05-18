UAM Agent - Source-based deployment (no .exe, no Defender problems)
====================================================================

WHY THIS EXISTS
---------------
The pkg-built .exe gets quarantined by Windows Defender on most Windows 10/11
machines. Workarounds (yao-pkg, exclusions, IExpress) are unreliable. The
proper solutions are (a) a code-signing certificate or (b) running the agent
as plain Node.js source. This bundle does (b).

The Node.js installer is signed by the OpenJS Foundation. Defender does not
flag node.exe. Once Node is installed on a client, the agent runs straight
from .js files and no .exe is involved.

ONE-TIME PREP (on your build/dev machine)
-----------------------------------------
1. Download the Node.js 20 LTS Windows MSI:
       https://nodejs.org/dist/v20.18.0/node-v20.18.0-x64.msi
   Save it as:
       deploy\node-source-bundle\node-v20.18.0-x64.msi

2. Run prepare.bat to assemble the agent:
       cd deploy\node-source-bundle
       prepare.bat

   This produces an 'agent\' subfolder containing the agent source plus
   already-installed node_modules (so the client doesn't need to npm install).

PER-MACHINE INSTALL
-------------------
Copy the ENTIRE 'node-source-bundle' folder to the client (any temp path is
fine), then right-click install.bat -> Run as administrator.

The installer:
  - Installs Node.js silently if not already present.
  - Copies the agent to C:\Program Files\UAMAgent\.
  - Registers the Windows service "UAM Activity Agent" using node-windows.
  - Starts the service.

UNINSTALL
---------
Right-click uninstall.bat -> Run as administrator.

MASS DEPLOYMENT
---------------
Same as the .exe-based deploy, but ship this folder instead. Either:
  - Group Policy startup script (point gpo-startup.bat at this install.bat).
  - PsExec push (deploy-remote.bat in ..\).
  - Intune/SCCM as a Win32 app (install: install.bat, detect: presence of
    C:\Program Files\UAMAgent\src\index.js).

UPDATING LATER
--------------
To push a new agent version:
  1. Update src\ on the dev machine, run prepare.bat again.
  2. Re-deploy the bundle.
  3. install.bat removes the old service and re-registers the new files.

WHAT GETS INSTALLED ON A CLIENT
-------------------------------
  C:\Program Files\nodejs\          (Node 20 LTS, signed by OpenJS)
  C:\Program Files\UAMAgent\
      package.json
      config.json
      src\
      node_modules\
      service\install-service.js
  C:\ProgramData\UAMAgent\
      spool\
      agent.log
  Windows service "UAM Activity Agent" (LocalSystem, autostart)

FOOTPRINT
---------
  Node.js installed: ~50 MB
  Agent files:       ~15 MB (mostly node_modules — axios, uuid, node-windows)
  Total:             ~65 MB on disk
  RAM at idle:       ~40 MB

That's larger than a single 25 MB compressed .exe, but the trade-off is a
deployment that actually works without fighting AV.
