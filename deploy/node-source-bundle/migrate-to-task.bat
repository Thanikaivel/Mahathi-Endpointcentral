@echo off
REM ============================================================================
REM  UAM Agent - MIGRATE existing install from NSSM service -> Scheduled Task
REM
REM  Use this on machines that ALREADY have the agent installed at
REM  C:\Program Files\UAMAgent\ via install.bat. It does NOT copy any files;
REM  it just removes the NSSM service and registers a Scheduled Task pointing
REM  at the existing install.
REM
REM  Tiny standalone script - no bundle needed. Push just this one .bat file.
REM
REM  Run as Administrator.
REM ============================================================================
setlocal

set "INSTALL_DIR=C:\Program Files\UAMAgent"
set "DATA_DIR=C:\ProgramData\UAMAgent"
set "TASK_NAME=UAMAgent"
set "OLD_SERVICE=UAM Activity Agent"

net session >nul 2>&1
if errorlevel 1 ( echo [ERR] Run as Administrator. & exit /b 1 )

REM --- 1. Sanity-check: existing install must be present ---
echo [1/4] Verifying existing agent install...
if not exist "%INSTALL_DIR%\src\index.js" (
  echo [ERR] %INSTALL_DIR%\src\index.js not found.
  echo This machine doesn't appear to have the agent installed.
  echo Use install-as-task.bat with the full bundle instead.
  exit /b 2
)
if not exist "C:\Program Files\nodejs\node.exe" (
  echo [ERR] Node.js not found at C:\Program Files\nodejs\node.exe
  exit /b 3
)
echo Existing install OK at %INSTALL_DIR%.

REM --- 2. Stop & remove the NSSM service ---
echo [2/4] Removing NSSM service "%OLD_SERVICE%"...
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
  echo Service removed.
) else (
  echo No NSSM service found - skipping.
)

REM --- 3. Make data dir writable for all users (agent now runs per-user) ---
echo [3/4] Adjusting permissions on %DATA_DIR%...
if not exist "%DATA_DIR%\spool" mkdir "%DATA_DIR%\spool"
icacls "%DATA_DIR%" /grant "Users:(OI)(CI)M" /T >nul

REM Write the hidden VBS launcher (idempotent)
> "%INSTALL_DIR%\run-hidden.vbs" echo Set WshShell = CreateObject("WScript.Shell")
>>"%INSTALL_DIR%\run-hidden.vbs" echo WshShell.Run """C:\Program Files\nodejs\node.exe"" ""C:\Program Files\UAMAgent\src\index.js""", 0, False

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

REM Start it now for the current interactive user, if any
schtasks /Run /TN "%TASK_NAME%" >nul 2>&1

del "%TASK_XML%" >nul 2>&1

echo.
echo === Migration complete ===
echo Agent now runs as a Scheduled Task on user logon.
echo Verify:    tasklist /FI "IMAGENAME eq node.exe" /v /fo list
echo Logs:      %DATA_DIR%\agent.log
endlocal
exit /b 0
