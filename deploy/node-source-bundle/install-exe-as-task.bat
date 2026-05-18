@echo off
REM ============================================================================
REM  UAM Agent - FRESH EXE INSTALL + Scheduled Task
REM
REM  Lightweight installer for clean machines. Drops the standalone uam-agent.exe
REM  binary in place and registers a Scheduled Task that launches it as the
REM  logged-on user (no Session 0 isolation).
REM
REM  Push these THREE files to each target machine:
REM     install-exe-as-task.bat       (this file)
REM     uam-agent.exe                  (the pkg-built standalone binary)
REM     config.json                    (endpoint + agent key)
REM
REM  Place all three in the same folder, then run install-exe-as-task.bat as
REM  Administrator.
REM ============================================================================
setlocal

set "INSTALL_DIR=C:\ProgramData\UAMAgent\uam-agent"
set "DATA_DIR=C:\ProgramData\UAMAgent"
set "AGENT_EXE_DEST=%INSTALL_DIR%\uam-agent.exe"
set "TASK_NAME=UAMAgent"
set "SOURCE=%~dp0"

net session >nul 2>&1
if errorlevel 1 ( echo [ERR] Run as Administrator. & exit /b 1 )

REM --- 0. Validate the three files are in the bundle ---
echo [0/5] Validating bundle...
if not exist "%SOURCE%uam-agent.exe"   goto :missing_exe
if not exist "%SOURCE%config.json"     goto :missing_cfg
echo Bundle looks good.
goto :step1

:missing_exe
echo [ERR] %SOURCE%uam-agent.exe not found next to this script.
exit /b 10

:missing_cfg
echo [ERR] %SOURCE%config.json not found next to this script.
exit /b 11

:step1
REM --- 1. Stop & remove any prior install (idempotent upgrade) ---
echo [1/5] Removing prior install if present...

REM Any NSSM-managed services under known names
for %%S in ("uam-agent" "UAM Activity Agent") do (
  sc query %%S >nul 2>&1
  if not errorlevel 1 (
    echo   Stopping and removing service: %%S
    sc stop %%S >nul 2>&1
    timeout /t 2 /nobreak >nul
    sc delete %%S >nul 2>&1
  )
)

REM Existing scheduled task
schtasks /End    /TN "%TASK_NAME%" >nul 2>&1
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1

REM Kill any running agent process so we can overwrite the binary
taskkill /F /IM uam-agent.exe >nul 2>&1
timeout /t 2 /nobreak >nul

REM --- 2. Copy the agent files into place ---
echo [2/5] Installing agent to %INSTALL_DIR% ...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%DATA_DIR%\spool" mkdir "%DATA_DIR%\spool"
copy /Y "%SOURCE%uam-agent.exe" "%AGENT_EXE_DEST%" >nul || ( echo [ERR] Failed to copy uam-agent.exe & exit /b 4 )
copy /Y "%SOURCE%config.json"   "%INSTALL_DIR%\config.json" >nul || ( echo [ERR] Failed to copy config.json & exit /b 5 )

REM --- 3. Permissions (Users need RX on the exe, M on data) ---
echo [3/5] Setting permissions...
icacls "%INSTALL_DIR%" /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "Users:(OI)(CI)RX" /T >nul
icacls "%DATA_DIR%"    /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "Users:(OI)(CI)M"  /T >nul

REM --- 4. (Optional but recommended) Defender exclusion for the install dir ---
echo [4/5] Adding Defender path exclusion for %INSTALL_DIR%...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Add-MpPreference -ExclusionPath '%INSTALL_DIR%' -ErrorAction Stop; Write-Host 'Defender exclusion added.' } catch { Write-Host 'Defender exclusion not applied (may already be set or Defender not present).' }" 2>nul

REM --- 5. Register the scheduled task ---
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
>>"%TASK_XML%" echo       ^<Command^>%AGENT_EXE_DEST%^</Command^>
>>"%TASK_XML%" echo       ^<WorkingDirectory^>%INSTALL_DIR%^</WorkingDirectory^>
>>"%TASK_XML%" echo     ^</Exec^>
>>"%TASK_XML%" echo   ^</Actions^>
>>"%TASK_XML%" echo ^</Task^>

REM Re-encode the XML to UTF-16 LE (schtasks requires this)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$c = Get-Content -Raw -Encoding ASCII '%TASK_XML%'; [System.IO.File]::WriteAllText('%TASK_XML%', $c, [System.Text.UnicodeEncoding]::new($false, $true))"

schtasks /Create /TN "%TASK_NAME%" /XML "%TASK_XML%" /F
if errorlevel 1 ( echo [ERR] Task creation failed.& exit /b 6 )

REM Start the task for the current interactive user, if any
schtasks /Run /TN "%TASK_NAME%" >nul 2>&1
del "%TASK_XML%" >nul 2>&1

echo.
echo === Install complete ===
echo Agent:  %AGENT_EXE_DEST%
echo Logs:   %DATA_DIR%\agent.log
echo Task:   %TASK_NAME%  (triggers on any user logon)
echo Verify: tasklist /FI "IMAGENAME eq uam-agent.exe" /v /fo list
endlocal
exit /b 0
