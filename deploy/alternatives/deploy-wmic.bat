@echo off
REM ============================================================================
REM  Push agent install via WMIC (Win32_Process.Create). No PsExec required.
REM
REM  Prerequisites on EACH target:
REM    - Admin C$ share reachable from your workstation.
REM    - Remote WMI allowed through firewall (typically open in domain profile).
REM    - You're in an elevated CMD with rights to the targets.
REM
REM  How it works:
REM    1. Copies the bundle to \\HOST\C$\Windows\Temp\UAMAgent-Install\
REM    2. Asks WMI to spawn a SYSTEM-owned cmd.exe that runs install.bat
REM
REM  Edit machines.txt (one host per line) and run this elevated.
REM ============================================================================
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-13%"
REM ROOT now points to the deploy\ folder
set "BUNDLE=%ROOT%bundle"
set "REMOTE_DIR=C$\Windows\Temp\UAMAgent-Install"
set "REMOTE_LOCAL=C:\Windows\Temp\UAMAgent-Install"
set "LIST=%ROOT%machines.txt"

if not exist "%BUNDLE%\uam-agent.exe" ( echo [ERR] %BUNDLE%\uam-agent.exe missing.& exit /b 1 )
if not exist "%LIST%"                  ( echo [ERR] %LIST% missing.& exit /b 1 )

set OK=0
set FAIL=0

for /f "usebackq eol=# tokens=* delims=" %%H in ("%LIST%") do (
  set "HOST=%%H"
  if not "!HOST!"=="" (
    echo === !HOST! =================================================
    if not exist "\\!HOST!\!REMOTE_DIR!" mkdir "\\!HOST!\!REMOTE_DIR!" 2>nul
    xcopy /E /I /Y /Q "%BUNDLE%\*" "\\!HOST!\!REMOTE_DIR!\" >nul
    if errorlevel 1 (
      echo   [FAIL ] copy
      set /a FAIL+=1
    ) else (
      wmic /node:"!HOST!" process call create "cmd /c \"!REMOTE_LOCAL!\install.bat > !REMOTE_LOCAL!\install.log 2>&1\"" | findstr /C:"ProcessId"
      if errorlevel 1 (
        echo   [FAIL ] wmic spawn
        set /a FAIL+=1
      ) else (
        echo   [ OK  ] install kicked off — see \\!HOST!\!REMOTE_DIR!\install.log
        set /a OK+=1
      )
    )
  )
)

echo.
echo Success: !OK!   Failed: !FAIL!
endlocal
