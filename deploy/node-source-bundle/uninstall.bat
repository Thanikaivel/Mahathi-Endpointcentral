@echo off
setlocal
set "INSTALL_DIR=C:\Program Files\UAMAgent"
set "DATA_DIR=C:\ProgramData\UAMAgent"
set "SERVICE_NAME=UAM Activity Agent"

net session >nul 2>&1
if errorlevel 1 ( echo Run as Administrator. & exit /b 1 )

echo Stopping service...
sc stop "%SERVICE_NAME%" >nul 2>&1
timeout /t 3 /nobreak >nul

if exist "%INSTALL_DIR%\service\uninstall-service.js" (
  pushd "%INSTALL_DIR%"
  "C:\Program Files\nodejs\node.exe" service\uninstall-service.js
  popd
  timeout /t 3 /nobreak >nul
)
sc delete "%SERVICE_NAME%" >nul 2>&1

if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
echo Spool/log data left at %DATA_DIR%
echo Uninstalled. Node.js was NOT removed (other apps may use it).
endlocal
