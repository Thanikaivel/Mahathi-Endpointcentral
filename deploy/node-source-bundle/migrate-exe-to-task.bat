@echo off
REM ============================================================================
REM  UAM Agent - MIGRATE existing EXE-based NSSM install -> Scheduled Task
REM
REM  For machines deployed via uam-agent.ps1 with this layout:
REM     C:\ProgramData\UAMAgent\uam-agent\uam-agent.exe
REM     C:\ProgramData\UAMAgent\nssm.exe
REM     C:\ProgramData\UAMAgent\spool\
REM     NSSM service: "uam-agent"
REM
REM  Push just this one .bat file to each of the 50 machines and run as Admin.
REM ============================================================================
setlocal

set "DATA_DIR=C:\ProgramData\UAMAgent"
set "AGENT_DIR=%DATA_DIR%\uam-agent"
set "AGENT_EXE=%AGENT_DIR%\uam-agent.exe"
set "TASK_NAME=UAMAgent"
set "OLD_SERVICE=uam-agent"

net session >nul 2>&1
if errorlevel 1 ( echo [ERR] Run as Administrator. & exit /b 1 )

REM --- 1. Sanity check ---
echo [1/4] Verifying existing install...
if not exist "%AGENT_EXE%" (
  echo [ERR] %AGENT_EXE% not found.
  echo This machine does not appear to have the EXE-based agent installed.
  exit /b 2
)
echo Found agent at: %AGENT_EXE%

REM --- 2. Stop & remove the NSSM service ---
echo [2/4] Removing NSSM service "%OLD_SERVICE%"...
sc query "%OLD_SERVICE%" >nul 2>&1
if not errorlevel 1 (
  REM Use nssm if available for cleaner shutdown
  if exist "%DATA_DIR%\nssm.exe" (
    "%DATA_DIR%\nssm.exe" stop "%OLD_SERVICE%" >nul 2>&1
    timeout /t 3 /nobreak >nul
    "%DATA_DIR%\nssm.exe" remove "%OLD_SERVICE%" confirm >nul 2>&1
  ) else (
    sc stop "%OLD_SERVICE%" >nul 2>&1
    timeout /t 3 /nobreak >nul
    sc delete "%OLD_SERVICE%" >nul 2>&1
  )
  REM Belt and suspenders - sc delete in case nssm remove didn't fully drop it
  sc delete "%OLD_SERVICE%" >nul 2>&1
  echo Service removed.
) else (
  echo No NSSM service named '%OLD_SERVICE%' found - skipping.
)

REM Also remove the alternate service name in case it was installed both ways
sc query "UAM Activity Agent" >nul 2>&1
if not errorlevel 1 (
  echo Also removing legacy "UAM Activity Agent" service...
  sc stop "UAM Activity Agent" >nul 2>&1
  timeout /t 3 /nobreak >nul
  sc delete "UAM Activity Agent" >nul 2>&1
)

REM --- 3. Permissions: data dir must be writable for all users (agent runs per-user now) ---
echo [3/4] Adjusting permissions on %DATA_DIR%...
if not exist "%DATA_DIR%\spool" mkdir "%DATA_DIR%\spool"
icacls "%DATA_DIR%"  /grant "Users:(OI)(CI)M" /T >nul
icacls "%AGENT_DIR%" /grant "Users:(OI)(CI)RX" /T >nul

REM --- 4. Register the Scheduled Task ---
echo [4/4] Registering scheduled task "%TASK_NAME%"...

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
>>"%TASK_XML%" echo       ^<Command^>%AGENT_EXE%^</Command^>
>>"%TASK_XML%" echo       ^<WorkingDirectory^>%AGENT_DIR%^</WorkingDirectory^>
>>"%TASK_XML%" echo     ^</Exec^>
>>"%TASK_XML%" echo   ^</Actions^>
>>"%TASK_XML%" echo ^</Task^>

REM Re-encode the XML to UTF-16 LE (schtasks requires this)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$c = Get-Content -Raw -Encoding ASCII '%TASK_XML%'; [System.IO.File]::WriteAllText('%TASK_XML%', $c, [System.Text.UnicodeEncoding]::new($false, $true))"

schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
schtasks /Create /TN "%TASK_NAME%" /XML "%TASK_XML%" /F
if errorlevel 1 ( echo [ERR] Task creation failed.& exit /b 5 )

REM Start it now for the current interactive user, if any
schtasks /Run /TN "%TASK_NAME%" >nul 2>&1

del "%TASK_XML%" >nul 2>&1

echo.
echo === Migration complete ===
echo Agent now runs as a Scheduled Task on user logon.
echo Verify:    tasklist /FI "IMAGENAME eq uam-agent.exe" /v /fo list
echo Logs:      %DATA_DIR%\agent.log
echo            %AGENT_DIR%\uam-agent.out.log  (NSSM-era log, may grow stale)
echo.
echo NOTE: The dashboard may still show an orphan "old session" row for this
echo machine for up to 15 minutes after migration. On the backend, run:
echo        EXEC dbo.usp_CloseStaleSessions @StaleMinutes = 1;
echo to close the orphan immediately. Then refresh the dashboard.
endlocal
exit /b 0
