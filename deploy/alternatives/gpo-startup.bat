@echo off
REM ============================================================================
REM  UAM Agent — Group Policy Startup Script
REM
REM  Place this file plus the contents of \deploy\bundle\ on the SYSVOL share:
REM     \\domain.local\sysvol\domain.local\scripts\UAMAgent\
REM         gpo-startup.bat       (this file)
REM         install.bat
REM         uninstall.bat
REM         uam-agent.exe
REM         config.json
REM
REM  Then in Group Policy Management:
REM     - Edit the GPO scoped to the OU(s) with your 300 machines
REM     - Computer Configuration -> Policies -> Windows Settings -> Scripts (Startup/Shutdown)
REM     - Startup -> Add -> Script Name = gpo-startup.bat
REM
REM  GPO startup scripts run as SYSTEM, before any user logs on. Each machine
REM  installs at next reboot. The marker file makes this idempotent: subsequent
REM  reboots do nothing once the agent's installed version matches the bundle.
REM ============================================================================
setlocal

set "MARKER=C:\ProgramData\UAMAgent\.installed-version"
set "VERSION_NOW=1.0.0"
set "BUNDLE=%~dp0"
set "INSTALLER=%BUNDLE%install.bat"

REM Skip if same version is already installed
if exist "%MARKER%" (
  for /f "usebackq tokens=*" %%v in ("%MARKER%") do (
    if "%%v"=="%VERSION_NOW%" (
      echo [%date% %time%] UAM Agent v%VERSION_NOW% already installed; skipping. >> C:\Windows\Temp\uam-gpo-startup.log
      exit /b 0
    )
  )
)

echo [%date% %time%] Installing UAM Agent v%VERSION_NOW% from %BUNDLE% >> C:\Windows\Temp\uam-gpo-startup.log
call "%INSTALLER%"             >> C:\Windows\Temp\uam-gpo-startup.log 2>&1

if %ERRORLEVEL% equ 0 (
  if not exist "C:\ProgramData\UAMAgent" mkdir "C:\ProgramData\UAMAgent"
  > "%MARKER%" echo %VERSION_NOW%
  echo [%date% %time%] Install OK. Marker written. >> C:\Windows\Temp\uam-gpo-startup.log
) else (
  echo [%date% %time%] Install FAILED with code %ERRORLEVEL% >> C:\Windows\Temp\uam-gpo-startup.log
)

endlocal
exit /b 0
