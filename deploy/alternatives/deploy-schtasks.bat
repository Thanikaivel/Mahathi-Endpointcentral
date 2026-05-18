@echo off
REM ============================================================================
REM  Push agent install via remote schtasks. Useful when both PsExec and WMI are
REM  locked down but standard RPC (used by 'schtasks /s') is permitted.
REM
REM  For each host:
REM    1. Copies bundle to \\HOST\C$\Windows\Temp\UAMAgent-Install\
REM    2. Creates a one-shot scheduled task that runs install.bat as SYSTEM
REM    3. Triggers it immediately, then deletes it
REM
REM  Pass /U DOMAIN\admin /P P@ssw0rd if your current creds aren't enough.
REM ============================================================================
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-13%"
set "BUNDLE=%ROOT%bundle"
set "LIST=%ROOT%machines.txt"
set "TASK_NAME=UAMAgent_Install"

REM Optional creds
set "USER="
set "PASS="
:parseargs
if /i "%~1"=="/U" ( set "USER=%~2" & shift & shift & goto parseargs )
if /i "%~1"=="/P" ( set "PASS=%~2" & shift & shift & goto parseargs )

if not exist "%BUNDLE%\uam-agent.exe" ( echo [ERR] %BUNDLE%\uam-agent.exe missing.& exit /b 1 )
if not exist "%LIST%"                  ( echo [ERR] %LIST% missing.& exit /b 1 )

set "AUTH="
if defined USER set "AUTH=/U %USER% /P %PASS%"

set OK=0
set FAIL=0

for /f "usebackq eol=# tokens=* delims=" %%H in ("%LIST%") do (
  set "HOST=%%H"
  if not "!HOST!"=="" (
    echo === !HOST! ====================================================
    REM Stage files via admin share
    if not exist "\\!HOST!\C$\Windows\Temp\UAMAgent-Install" mkdir "\\!HOST!\C$\Windows\Temp\UAMAgent-Install" 2>nul
    xcopy /E /I /Y /Q "%BUNDLE%\*" "\\!HOST!\C$\Windows\Temp\UAMAgent-Install\" >nul || ( set /a FAIL+=1 & echo   [FAIL] copy & goto :next )

    REM Create task
    schtasks /Create /S !HOST! %AUTH% /TN "%TASK_NAME%" /TR "cmd /c C:\Windows\Temp\UAMAgent-Install\install.bat" /SC ONCE /ST 23:59 /RU SYSTEM /F >nul
    if errorlevel 1 ( set /a FAIL+=1 & echo   [FAIL] create task & goto :next )

    REM Run now
    schtasks /Run /S !HOST! %AUTH% /TN "%TASK_NAME%" >nul
    if errorlevel 1 ( set /a FAIL+=1 & echo   [FAIL] run task & goto :next )

    REM Wait a bit, then delete (the install.bat itself completes in seconds)
    timeout /t 8 /nobreak >nul
    schtasks /Delete /S !HOST! %AUTH% /TN "%TASK_NAME%" /F >nul

    echo   [ OK ] !HOST! installed
    set /a OK+=1
    :next
  )
)

echo.
echo Success: !OK!   Failed: !FAIL!
endlocal
