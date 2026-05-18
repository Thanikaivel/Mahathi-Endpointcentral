@echo off
REM ============================================================================
REM  UAM Activity Agent - per-machine uninstaller
REM  Run as Administrator.
REM ============================================================================
setlocal

set "INSTALL_DIR=C:\Program Files\UAMAgent"
set "DATA_DIR=C:\ProgramData\UAMAgent"
set "SERVICE_NAME=UAM Activity Agent"

net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] uninstall.bat must be run as Administrator.
  exit /b 1
)

echo Stopping "%SERVICE_NAME%" ...
sc query "%SERVICE_NAME%" >nul 2>&1
if not errorlevel 1 (
  sc stop "%SERVICE_NAME%" >nul 2>&1
  for /l %%i in (1,1,10) do (
    sc query "%SERVICE_NAME%" | find /i "STOPPED" >nul && goto :stopped
    timeout /t 1 /nobreak >nul
  )
  :stopped
  sc delete "%SERVICE_NAME%" >nul 2>&1
  timeout /t 2 /nobreak >nul
)

echo Removing program files ...
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"

echo Spool/log data left at "%DATA_DIR%".
echo To remove it too:  rmdir /s /q "%DATA_DIR%"
echo.
echo Uninstalled.
endlocal
exit /b 0
