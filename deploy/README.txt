UAM Activity Agent — Deployment Kit
====================================

This folder is the install bundle you copy to each of the 300 client machines.

CONTENTS
--------
deploy/
   bundle/
       uam-agent.exe      <- you must drop this in here (built via npm run build:exe)
       config.json        <- edit apiBaseUrl + agentKey before deploying
       install.bat        <- runs on each client (must be elevated)
       uninstall.bat      <- runs on each client (must be elevated)
   machines.txt           <- list of target hostnames (one per line)
   deploy-remote.bat      <- pushes the bundle to every machine in machines.txt
                             using PsExec (no PSRemoting required)
   deploy-remote.ps1      <- alternative push using PowerShell remoting
                             (no extra tool required, but PSRemoting must be enabled)
   README.txt             <- this file

PREPARING THE BUNDLE (one time, on the build/admin machine)
-----------------------------------------------------------
1. Build uam-agent.exe:
       cd "..\..\client-agent-Dev"
       npm run build:exe
       copy /Y dist\uam-agent.exe "..\deploy\bundle\uam-agent.exe"
2. Edit deploy\bundle\config.json:
       - apiBaseUrl   -> http://build.mahathiinfotech.com:5321/api
       - agentKey     -> must match AGENT_SHARED_KEY in backend\.env
3. (Optional) test on one machine: copy the whole 'bundle' folder to that
   machine, right-click install.bat -> Run as administrator.

INSTALLING ON A SINGLE MACHINE
------------------------------
1. Copy the entire 'bundle' folder to the client (any temp path is fine).
2. Right-click install.bat -> Run as administrator.

UNINSTALLING ON A SINGLE MACHINE
--------------------------------
Right-click uninstall.bat -> Run as administrator.

PUSHING TO ALL 300 MACHINES
---------------------------
Option A — PsExec (recommended for AD environments):
   1. Download PsExec.exe from
      https://learn.microsoft.com/sysinternals/downloads/psexec
      and put it next to deploy-remote.bat.
   2. Edit machines.txt — one hostname or IP per line, no header.
   3. Open an elevated CMD (as a domain admin) and run:
          deploy-remote.bat
      Or with explicit credentials:
          deploy-remote.bat CORP\admin "P@ssw0rd"

Option B — PowerShell remoting:
   1. Make sure PSRemoting is enabled on targets:
          Enable-PSRemoting -Force      (run once on each, via GPO is easiest)
   2. Edit machines.txt.
   3. From an elevated PowerShell:
          .\deploy-remote.ps1
      Or with credentials:
          .\deploy-remote.ps1 -Credential (Get-Credential)

VERIFYING A DEPLOYMENT
----------------------
On any client machine:
   sc query "UAM Activity Agent"
   type C:\ProgramData\UAMAgent\agent.log

On the dashboard:
   http://build.mahathiinfotech.com/   ->  Machines page should list it
   within ~1 minute of the service starting.
