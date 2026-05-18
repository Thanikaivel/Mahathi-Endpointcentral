@echo off
REM ============================================================================
REM  Push UAM Activity Agent to every machine in machines.txt using PsExec.
REM
REM  Prerequisites:
REM    1. PsExec.exe (Sysinternals) sits in this folder.
REM    2. machines.txt has one hostname per line (# comments allowed).
REM    3. You run this from an elevated CMD with credentials that have local
REM       admin rights on every target (e.g. a domain admin).
REM
REM  Usage:
REM    deploy-remote.bat
REM    deploy-remote.bat CORP\admin "P@ssw0rd"
REM ============================================================================
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "BUNDLE=%ROOT%bundle"
set "REMOTE_DIR=C$\Windows\Temp\UAMAgent-Install"
set "REMOTE_LOCAL=C:\Windows\Temp\UAMAgent-Install"
set "USER=%~1"
set "PASS=%~2"

if not exist "%ROOT%PsExec.exe" (
  echo [ERROR] PsExec.exe not found in "%ROOT%".
  echo Download from https://learn.microsoft.com/sysinternals/downloads/psexec
  exit /b 1
)
if not exist "%ROOT%machines.txt" (
  echo [ERROR] machines.txt not found.
  exit /b 1
)
if not exist "%BUNDLE%\uam-agent.exe" (
  echo [ERROR] %BUNDLE%\uam-agent.exe is missing. Build it first.
  exit /b 1
)
if not exist "%BUNDLE%\config.json" (
  echo [ERROR] %BUNDLE%\config.json is missing.
  exit /b 1
)

set OK=0
set FAIL=0

for /f "usebackq eol=# tokens=* delims=" %%H in ("%ROOT%machines.txt") do (
  set "HOST=%%H"
  if not "!HOST!"=="" (
    echo.
    echo === !HOST! ============================================================
    REM 1. Stage files via the admin C$ share
    echo   [stage] Copying bundle to \\!HOST!\!REMOTE_DIR! ...
    if not exist "\\!HOST!\!REMOTE_DIR!" mkdir "\\!HOST!\!REMOTE_DIR!" 2>nul
    xcopy /E /I /Y /Q "%BUNDLE%\*" "\\!HOST!\!REMOTE_DIR!\" >nul
    if errorlevel 1 (
      echo   [FAIL ] Could not copy bundle. Check admin share access.
      set /a FAIL+=1
    ) else (
      REM 2. Run install.bat as SYSTEM
      echo   [run  ] Executing install.bat ...
      if defined USER (
        "%ROOT%PsExec.exe" \\!HOST! -u "!USER!" -p "!PASS!" -s -accepteula -nobanner -h cmd /c "!REMOTE_LOCAL!\install.bat"
      ) else (
        "%ROOT%PsExec.exe" \\!HOST! -s -accepteula -nobanner -h cmd /c "!REMOTE_LOCAL!\install.bat"
      )
      if errorlevel 1 (
        echo   [FAIL ] install.bat returned non-zero on !HOST!.
        set /a FAIL+=1
      ) else (
        echo   [ OK  ] !HOST! installed.
        set /a OK+=1
      )
    )
  )
)

echo.
echo ============================================================================
echo Done. Success: !OK!   Failed: !FAIL!
echo ============================================================================
endlocal
exit /b 0
