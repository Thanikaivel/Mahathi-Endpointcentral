@echo off
REM ============================================================================
REM  UAM Agent - FULL UNINSTALL
REM
REM  Wipes every variant of the agent off this machine:
REM    - Stops & removes NSSM services (any known name)
REM    - Kills any running uam-agent.exe / node.exe agent processes
REM    - Removes the UAMAgent scheduled task
REM    - Deletes C:\Program Files\UAMAgent\ (source-based install dir)
REM    - Deletes C:\ProgramData\UAMAgent\  (EXE-based install + data dir)
REM
REM  Run as Administrator.
REM ============================================================================
setlocal

net session >nul 2>&1
if errorlevel 1 ( echo [ERR] Run as Administrator. & exit /b 1 )

echo === UAM Agent - Full Uninstall ===
echo.

REM --- 1. Stop and remove NSSM services (under any known name) ---
echo [1/5] Removing NSSM services...
for %%S in ("uam-agent" "UAM Activity Agent" "UAMAgent") do (
  sc query %%S >nul 2>&1
  if not errorlevel 1 (
    echo   Stopping and removing service: %%S
    if exist "C:\ProgramData\UAMAgent\nssm.exe" (
      "C:\ProgramData\UAMAgent\nssm.exe" stop %%S >nul 2>&1
      timeout /t 2 /nobreak >nul
      "C:\ProgramData\UAMAgent\nssm.exe" remove %%S confirm >nul 2>&1
    ) else (
      sc stop %%S >nul 2>&1
      timeout /t 2 /nobreak >nul
    )
    sc delete %%S >nul 2>&1
  )
)

REM --- 2. Remove the scheduled task ---
echo [2/5] Removing scheduled task UAMAgent...
schtasks /End    /TN "UAMAgent" >nul 2>&1
schtasks /Delete /TN "UAMAgent" /F >nul 2>&1

REM --- 3. Kill any running agent processes ---
echo [3/5] Killing any running agent processes...
taskkill /F /IM uam-agent.exe >nul 2>&1
REM Also kill any node.exe that's running the agent's index.js (source-based deploy)
for /f "tokens=2 delims=," %%P in ('tasklist /v /fo csv /nh 2^>nul ^| findstr /i "UAMAgent\\src\\index.js"') do (
  taskkill /F /PID %%~P >nul 2>&1
)
timeout /t 2 /nobreak >nul

REM --- 4. Delete install directories ---
echo [4/5] Deleting install directories...
if exist "C:\Program Files\UAMAgent\" (
  echo   Removing C:\Program Files\UAMAgent\
  rmdir /s /q "C:\Program Files\UAMAgent" 2>nul
)
if exist "C:\ProgramData\UAMAgent\" (
  echo   Removing C:\ProgramData\UAMAgent\
  rmdir /s /q "C:\ProgramData\UAMAgent" 2>nul
)

REM --- 5. Verify ---
echo [5/5] Verifying clean state...
set CLEAN=1
sc query uam-agent >nul 2>&1
if not errorlevel 1 ( echo   [WARN] Service 'uam-agent' still present. & set CLEAN=0 )
sc query "UAM Activity Agent" >nul 2>&1
if not errorlevel 1 ( echo   [WARN] Service 'UAM Activity Agent' still present. & set CLEAN=0 )
schtasks /Query /TN UAMAgent >nul 2>&1
if not errorlevel 1 ( echo   [WARN] Scheduled task 'UAMAgent' still present. & set CLEAN=0 )
if exist "C:\Program Files\UAMAgent\"  ( echo   [WARN] C:\Program Files\UAMAgent\ still exists.  & set CLEAN=0 )
if exist "C:\ProgramData\UAMAgent\"    ( echo   [WARN] C:\ProgramData\UAMAgent\ still exists.    & set CLEAN=0 )

echo.
if "%CLEAN%"=="1" (
  echo === Clean state confirmed. Machine is ready for fresh install. ===
) else (
  echo === WARN: Some artifacts remain. Reboot if files are locked, then re-run. ===
)
endlocal
exit /b 0
