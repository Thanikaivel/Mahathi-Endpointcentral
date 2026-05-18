@echo off
REM ============================================================================
REM  UAM Agent - SCHEDULED TASK installer (no service, no Session 0 isolation)
REM
REM  Use this instead of install.bat when NSSM service mode reports
REM  Active=0 because GetLastInputInfo can't see user input from Session 0.
REM
REM  This installer:
REM     1. Installs Node.js (silently, idempotent).
REM     2. Copies agent to C:\Program Files\UAMAgent\.
REM     3. Removes any existing NSSM service ("UAM Activity Agent").
REM     4. Registers a Scheduled Task "UAMAgent" that:
REM          - triggers on ANY user logon
REM          - runs as the logged-on user (not SYSTEM)
REM          - hidden, no console window
REM          - auto-restarts every minute on failure
REM
REM  Run as Administrator.
REM ============================================================================
setlocal

set "INSTALL_DIR=C:\Program Files\UAMAgent"
set "DATA_DIR=C:\ProgramData\UAMAgent"
set "TASK_NAME=UAMAgent"
set "OLD_SERVICE=UAM Activity Agent"
set "SOURCE=%~dp0"

REM Zip-based deployment: if uam-deploy.zip is present at C:\temp\, extract it
REM to C:\temp\uam-deploy\ and use that folder as the bundle source.
REM At the end of a successful install we delete the C:\temp\uam-deploy\ folder
REM (the .zip and any other files in C:\temp are LEFT ALONE).
set "DEPLOY_ZIP=C:\temp\uam-deploy.zip"
set "DEPLOY_DIR=C:\temp\uam-deploy"
set "CLEANUP_DEPLOY=0"

net session >nul 2>&1
if errorlevel 1 ( echo [ERR] Run as Administrator. & exit /b 1 )

if exist "%DEPLOY_ZIP%" (
  echo [*] Found %DEPLOY_ZIP% - unpacking to %DEPLOY_DIR%...
  if exist "%DEPLOY_DIR%" rmdir /s /q "%DEPLOY_DIR%"
  mkdir "%DEPLOY_DIR%" 2>nul
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Add-Type -AssemblyName System.IO.Compression.FileSystem; try { [System.IO.Compression.ZipFile]::ExtractToDirectory('%DEPLOY_ZIP%','%DEPLOY_DIR%') } catch { Write-Error $_.Exception.Message; exit 1 }"
  if errorlevel 1 ( echo [ERR] Failed to unzip %DEPLOY_ZIP%.& exit /b 20 )
  set "SOURCE=%DEPLOY_DIR%\"
  set "CLEANUP_DEPLOY=1"
  echo Unpacked. Using bundle from %DEPLOY_DIR%
)

REM Detect bundle layout - try these in order:
REM   A) %SOURCE%\agent\src\index.js          (bundle layout, .bat outside agent)
REM   B) %SOURCE%\src\index.js                (zip extracted directly, no agent\ wrapper)
REM   C) %SOURCE%\<single-subfolder>\src\index.js          (zip has wrapper folder)
REM   D) %SOURCE%\<single-subfolder>\agent\src\index.js    (zip has wrapper + agent\ wrapper)
setlocal EnableDelayedExpansion
set "AGENT_DIR=%SOURCE%agent"
if not exist "!AGENT_DIR!\src\index.js" (
  if exist "%SOURCE%src\index.js" (
    set "AGENT_DIR=%SOURCE:~0,-1%"
  ) else (
    REM Scan one level down for the agent files
    for /d %%D in ("%SOURCE%*") do (
      if exist "%%~D\agent\src\index.js" (
        set "AGENT_DIR=%%~D\agent"
      ) else if exist "%%~D\src\index.js" (
        set "AGENT_DIR=%%~D"
      )
    )
  )
)
endlocal & set "AGENT_DIR=%AGENT_DIR%"

REM --- 0. Validate bundle BEFORE touching anything ---
echo [0/5] Validating bundle...
echo Using agent source: %AGENT_DIR%
if not exist "%AGENT_DIR%\src\index.js"   goto :missing_src
if not exist "%AGENT_DIR%\node_modules\"  goto :missing_modules
if not exist "%AGENT_DIR%\config.json"    goto :missing_config
echo Bundle looks good.
goto :step1

:missing_src
echo.
echo [ERR] Required file not found:   %AGENT_DIR%\src\index.js
echo.
echo This bundle is incomplete. Expected one of these layouts next to this script:
echo.
echo   Layout A:  ^<folder^>\install-as-task.bat
echo              ^<folder^>\agent\src\index.js
echo              ^<folder^>\agent\config.json
echo              ^<folder^>\agent\node_modules\
echo.
echo   Layout B:  ^<folder^>\install-as-task.bat   ^(script INSIDE the agent folder^)
echo              ^<folder^>\src\index.js
echo              ^<folder^>\config.json
echo              ^<folder^>\node_modules\
echo.
echo To build the agent folder on the dev box run:
echo     deploy\node-source-bundle\prepare.bat
echo.
exit /b 11

:missing_modules
echo [ERR] %AGENT_DIR%\node_modules\ missing - run prepare.bat on dev box first.
exit /b 12

:missing_config
echo [ERR] %AGENT_DIR%\config.json missing.
exit /b 13

:step1

REM --- 1. Node.js ---
echo [1/5] Checking for Node.js...
where node >nul 2>&1
if not errorlevel 1 goto :node_ready

REM Node not found - look for the MSI in any plausible bundle location.
REM Using labels (not an if-block) so each "set" takes effect before the next line.
set "NODE_MSI="
if exist "%SOURCE%node-v20.18.0-x64.msi"        set "NODE_MSI=%SOURCE%node-v20.18.0-x64.msi"
if not defined NODE_MSI if exist "%AGENT_DIR%\node-v20.18.0-x64.msi"    set "NODE_MSI=%AGENT_DIR%\node-v20.18.0-x64.msi"
if not defined NODE_MSI if exist "%AGENT_DIR%\..\node-v20.18.0-x64.msi" set "NODE_MSI=%AGENT_DIR%\..\node-v20.18.0-x64.msi"
if not defined NODE_MSI goto :node_missing

echo Installing Node.js from %NODE_MSI% ...
msiexec /i "%NODE_MSI%" /qn /norestart ADDLOCAL=ALL
if errorlevel 1 ( echo [ERR] Node MSI install failed.& exit /b 3 )
set "PATH=%PATH%;C:\Program Files\nodejs"
goto :node_ready

:node_missing
echo [ERR] node-v20.18.0-x64.msi missing from bundle.
echo Checked: %SOURCE%node-v20.18.0-x64.msi
echo Checked: %AGENT_DIR%\node-v20.18.0-x64.msi
echo Checked: %AGENT_DIR%\..\node-v20.18.0-x64.msi
exit /b 2

:node_ready
for /f "tokens=*" %%v in ('node --version') do set "NODE_VER=%%v"
echo Node version: %NODE_VER%

REM --- 2. Stop & remove anything currently running ---
echo [2/5] Stopping any running UAM Agent (service, task, processes)...

REM (a) Remove the scheduled task FIRST so it can't auto-restart while we kill processes
schtasks /End    /TN "%TASK_NAME%" >nul 2>&1
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
timeout /t 2 /nobreak >nul

REM (c) Stop & remove any legacy NSSM service
sc query "%OLD_SERVICE%" >nul 2>&1
if not errorlevel 1 (
  sc stop "%OLD_SERVICE%" >nul 2>&1
  timeout /t 3 /nobreak >nul
  if exist "%INSTALL_DIR%\service\uninstall-service.js" (
    pushd "%INSTALL_DIR%"
    "C:\Program Files\nodejs\node.exe" service\uninstall-service.js >nul 2>&1
    popd
    timeout /t 3 /nobreak >nul
  )
  sc delete "%OLD_SERVICE%" >nul 2>&1
)

REM (d) Kill agent processes. Targets only ours by filtering on commandline.
REM Run each kill twice with a pause - covers the case where a process is
REM in the middle of respawning.
taskkill /F /IM uam-agent.exe /T >nul 2>&1
wmic process where "name='node.exe'       and commandline like '%%UAMAgent%%'" call terminate >nul 2>&1
wmic process where "name='wscript.exe'    and commandline like '%%UAMAgent%%'" call terminate >nul 2>&1
wmic process where "name='powershell.exe' and commandline like '%%UAMAgent%%'" call terminate >nul 2>&1
timeout /t 2 /nobreak >nul

REM Second pass for any stragglers
taskkill /F /IM uam-agent.exe /T >nul 2>&1
wmic process where "name='node.exe'       and commandline like '%%UAMAgent%%'" call terminate >nul 2>&1
wmic process where "name='wscript.exe'    and commandline like '%%UAMAgent%%'" call terminate >nul 2>&1
wmic process where "name='powershell.exe' and commandline like '%%UAMAgent%%'" call terminate >nul 2>&1
timeout /t 3 /nobreak >nul

REM --- 3. Copy agent files ---
echo [3/5] Copying agent to %INSTALL_DIR% ...
if exist "%INSTALL_DIR%" (
  rmdir /s /q "%INSTALL_DIR%" 2>nul
  REM If rmdir failed because a file is still locked, wait a bit and retry once.
  if exist "%INSTALL_DIR%" (
    echo Some files were still locked. Waiting 5 seconds and retrying...
    timeout /t 5 /nobreak >nul
    rmdir /s /q "%INSTALL_DIR%" 2>nul
  )
  if exist "%INSTALL_DIR%" (
    echo [ERR] Could not remove existing %INSTALL_DIR% - a process is still holding files open.
    echo Open Task Manager and end any node.exe / uam-agent.exe / wscript.exe processes related to UAMAgent, then re-run this installer.
    exit /b 14
  )
)
mkdir "%INSTALL_DIR%"
xcopy /E /I /Y "%AGENT_DIR%\*" "%INSTALL_DIR%\" >nul || ( echo [ERR] Copy failed.& exit /b 4 )

REM Spool & log dirs - all users need write so each user's agent can log/spool
if not exist "%DATA_DIR%\spool" mkdir "%DATA_DIR%\spool"
icacls "%INSTALL_DIR%" /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "Users:(OI)(CI)RX" /T >nul
icacls "%DATA_DIR%"    /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "Users:(OI)(CI)M" /T >nul

REM --- 4. Hidden launcher (VBS hides the cmd window so users never see it) ---
echo [4/5] Writing hidden launcher...
> "%INSTALL_DIR%\run-hidden.vbs" echo Set WshShell = CreateObject("WScript.Shell")
>>"%INSTALL_DIR%\run-hidden.vbs" echo WshShell.Run """C:\Program Files\nodejs\node.exe"" ""C:\Program Files\UAMAgent\src\index.js""", 0, False

REM --- 5. Register scheduled task via XML (any-user logon trigger) ---
echo [5/5] Registering scheduled task "%TASK_NAME%"...

set "TASK_XML=%TEMP%\uamagent-task.xml"
> "%TASK_XML%" echo ^<?xml version="1.0" encoding="UTF-16"?^>
>>"%TASK_XML%" echo ^<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^>
>>"%TASK_XML%" echo   ^<RegistrationInfo^>^<Description^>UAM Activity Agent^</Description^>^</RegistrationInfo^>
>>"%TASK_XML%" echo   ^<Triggers^>^<LogonTrigger^>^<Enabled^>true^</Enabled^>^</LogonTrigger^>^</Triggers^>
>>"%TASK_XML%" echo   ^<Principals^>^<Principal id="Author"^>^<GroupId^>S-1-5-32-545^</GroupId^>^<RunLevel^>LeastPrivilege^</RunLevel^>^</Principal^>^</Principals^>
>>"%TASK_XML%" echo   ^<Settings^>
>>"%TASK_XML%" echo     ^<MultipleInstancesPolicy^>IgnoreNew^</MultipleInstancesPolicy^>
>>"%TASK_XML%" echo     ^<DisallowStartIfOnBatteries^>false^</DisallowStartIfOnBatteries^>
>>"%TASK_XML%" echo     ^<StopIfGoingOnBatteries^>false^</StopIfGoingOnBatteries^>
>>"%TASK_XML%" echo     ^<AllowHardTerminate^>true^</AllowHardTerminate^>
>>"%TASK_XML%" echo     ^<StartWhenAvailable^>true^</StartWhenAvailable^>
>>"%TASK_XML%" echo     ^<RunOnlyIfNetworkAvailable^>false^</RunOnlyIfNetworkAvailable^>
>>"%TASK_XML%" echo     ^<IdleSettings^>^<StopOnIdleEnd^>false^</StopOnIdleEnd^>^<RestartOnIdle^>false^</RestartOnIdle^>^</IdleSettings^>
>>"%TASK_XML%" echo     ^<AllowStartOnDemand^>true^</AllowStartOnDemand^>
>>"%TASK_XML%" echo     ^<Enabled^>true^</Enabled^>
>>"%TASK_XML%" echo     ^<Hidden^>true^</Hidden^>
>>"%TASK_XML%" echo     ^<RunOnlyIfIdle^>false^</RunOnlyIfIdle^>
>>"%TASK_XML%" echo     ^<DisallowStartOnRemoteAppSession^>false^</DisallowStartOnRemoteAppSession^>
>>"%TASK_XML%" echo     ^<UseUnifiedSchedulingEngine^>true^</UseUnifiedSchedulingEngine^>
>>"%TASK_XML%" echo     ^<WakeToRun^>false^</WakeToRun^>
>>"%TASK_XML%" echo     ^<ExecutionTimeLimit^>PT0S^</ExecutionTimeLimit^>
>>"%TASK_XML%" echo     ^<Priority^>7^</Priority^>
>>"%TASK_XML%" echo     ^<RestartOnFailure^>^<Interval^>PT1M^</Interval^>^<Count^>999^</Count^>^</RestartOnFailure^>
>>"%TASK_XML%" echo   ^</Settings^>
>>"%TASK_XML%" echo   ^<Actions Context="Author"^>
>>"%TASK_XML%" echo     ^<Exec^>
>>"%TASK_XML%" echo       ^<Command^>wscript.exe^</Command^>
>>"%TASK_XML%" echo       ^<Arguments^>"C:\Program Files\UAMAgent\run-hidden.vbs"^</Arguments^>
>>"%TASK_XML%" echo     ^</Exec^>
>>"%TASK_XML%" echo   ^</Actions^>
>>"%TASK_XML%" echo ^</Task^>

REM Re-encode the XML to UTF-16 LE (schtasks requires this)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$c = Get-Content -Raw -Encoding ASCII '%TASK_XML%'; [System.IO.File]::WriteAllText('%TASK_XML%', $c, [System.Text.UnicodeEncoding]::new($false, $true))"

schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
schtasks /Create /TN "%TASK_NAME%" /XML "%TASK_XML%" /F
if errorlevel 1 ( echo [ERR] Task creation failed.& exit /b 5 )

REM Start the task now for the current interactive user, if any
schtasks /Run /TN "%TASK_NAME%" >nul 2>&1

del "%TASK_XML%" >nul 2>&1

REM --- 6. Clean up the unpacked deploy folder (keep the .zip) ---
if "%CLEANUP_DEPLOY%"=="1" (
  echo Cleaning up %DEPLOY_DIR%...
  rmdir /s /q "%DEPLOY_DIR%" 2>nul
)

echo.
echo Done. Agent will start automatically when any user logs on.
echo Logs:   %DATA_DIR%\agent.log
echo Manual: schtasks /Run /TN %TASK_NAME%
endlocal
exit /b 0
