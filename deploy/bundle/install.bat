@echo off
REM ============================================================================
REM  UAM Activity Agent - per-machine installer
REM  Run as Administrator from this folder. The folder must contain:
REM    - uam-agent.exe
REM    - config.json
REM    - install.bat (this file)
REM ============================================================================
setlocal

set "INSTALL_DIR=C:\Program Files\UAMAgent"
set "DATA_DIR=C:\ProgramData\UAMAgent"
set "SERVICE_NAME=UAM Activity Agent"
set "SOURCE_DIR=%~dp0"

REM --- Elevation check ---------------------------------------------------------
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] install.bat must be run as Administrator.
  exit /b 1
)

REM --- Source files exist? -----------------------------------------------------
if not exist "%SOURCE_DIR%uam-agent.exe" (
  echo [ERROR] uam-agent.exe not found next to install.bat.
  exit /b 2
)
if not exist "%SOURCE_DIR%config.json" (
  echo [ERROR] config.json not found next to install.bat.
  exit /b 2
)

echo [1/6] Stopping any existing "%SERVICE_NAME%" ...
sc query "%SERVICE_NAME%" >nul 2>&1
if not errorlevel 1 (
  sc stop   "%SERVICE_NAME%" >nul 2>&1
  REM give the service up to 10s to stop
  for /l %%i in (1,1,10) do (
    sc query "%SERVICE_NAME%" | find /i "STOPPED" >nul && goto :stopped
    timeout /t 1 /nobreak >nul
  )
  :stopped
  sc delete "%SERVICE_NAME%" >nul 2>&1
  timeout /t 2 /nobreak >nul
)

echo [2/6] Creating folders ...
if not exist "%INSTALL_DIR%"      mkdir "%INSTALL_DIR%"
if not exist "%DATA_DIR%\spool"   mkdir "%DATA_DIR%\spool"

echo [3/6] Copying files ...
copy /Y "%SOURCE_DIR%uam-agent.exe" "%INSTALL_DIR%\uam-agent.exe" >nul || goto :copy_fail
copy /Y "%SOURCE_DIR%config.json"   "%INSTALL_DIR%\config.json"   >nul || goto :copy_fail

echo [4/6] Granting permissions ...
icacls "%INSTALL_DIR%" /grant "SYSTEM:(OI)(CI)F"            /T >nul
icacls "%DATA_DIR%"    /grant "SYSTEM:(OI)(CI)F"            /T >nul
icacls "%DATA_DIR%"    /grant "BUILTIN\Administrators:(OI)(CI)F" /T >nul

echo [5/6] Registering Windows service ...
sc create "%SERVICE_NAME%" binPath= "\"%INSTALL_DIR%\uam-agent.exe\"" start= auto obj= LocalSystem DisplayName= "%SERVICE_NAME%" >nul || goto :svc_fail
sc description "%SERVICE_NAME%" "User Activity Monitoring Agent. Collects login/lock/app usage and reports to the UAM server." >nul
REM Auto-restart on crash: 60s, 60s, 60s; reset failure count after 24h.
sc failure "%SERVICE_NAME%" reset= 86400 actions= restart/60000/restart/60000/restart/60000 >nul

echo [6/6] Starting service ...
sc start "%SERVICE_NAME%" >nul
timeout /t 3 /nobreak >nul

sc query "%SERVICE_NAME%" | findstr /C:"STATE"
echo.
echo Done. Logs: %DATA_DIR%\agent.log
endlocal
exit /b 0

:copy_fail
echo [ERROR] Failed to copy files to "%INSTALL_DIR%".
endlocal
exit /b 3

:svc_fail
echo [ERROR] Failed to register the Windows service.
endlocal
exit /b 4
