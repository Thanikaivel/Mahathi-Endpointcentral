@echo off
REM ============================================================================
REM  UAM Agent - SOURCE-BASED installer (no .exe, no Defender pain)
REM
REM  Layout expected next to this file:
REM     install.bat
REM     uninstall.bat
REM     node-v20.18.0-x64.msi          <- official Node.js LTS installer
REM     agent\                         <- copy of client-agent\
REM         package.json
REM         package-lock.json
REM         config.json
REM         src\index.js
REM         src\... (all js files)
REM         src\ps\probe.ps1
REM         service\install-service.js
REM         node_modules\              <- prebuilt by you, see prepare.bat
REM
REM  Run as Administrator. The installer:
REM     1. Installs Node.js silently (skips if already present at v20+).
REM     2. Copies agent to C:\Program Files\UAMAgent\.
REM     3. Registers the Windows service via node-windows.
REM ============================================================================
setlocal

set "INSTALL_DIR=C:\Program Files\UAMAgent"
set "DATA_DIR=C:\ProgramData\UAMAgent"
set "SERVICE_NAME=UAM Activity Agent"
set "SOURCE=%~dp0"

net session >nul 2>&1
if errorlevel 1 ( echo [ERR] Run as Administrator. & exit /b 1 )

REM --- 1. Make sure Node.js is installed ---
echo [1/4] Checking for Node.js...
where node >nul 2>&1
if errorlevel 1 (
  echo Node.js not found. Installing from %SOURCE%node-v20.18.0-x64.msi ...
  if not exist "%SOURCE%node-v20.18.0-x64.msi" (
    echo [ERR] node-v20.18.0-x64.msi missing from bundle.
    echo Download from https://nodejs.org/dist/v20.18.0/node-v20.18.0-x64.msi
    exit /b 2
  )
  msiexec /i "%SOURCE%node-v20.18.0-x64.msi" /qn /norestart ADDLOCAL=ALL
  if errorlevel 1 ( echo [ERR] Node MSI install failed.& exit /b 3 )
  REM Refresh PATH so 'node' is available in this shell
  set "PATH=%PATH%;C:\Program Files\nodejs"
)

for /f "tokens=*" %%v in ('node --version') do set "NODE_VER=%%v"
echo Node version: %NODE_VER%

REM --- 2. Stop & clean up any prior install ---
echo [2/4] Removing any previous install...
sc query "%SERVICE_NAME%" >nul 2>&1
if not errorlevel 1 (
  sc stop "%SERVICE_NAME%" >nul 2>&1
  timeout /t 3 /nobreak >nul
  REM Try the node-windows uninstaller first (cleanest)
  if exist "%INSTALL_DIR%\service\uninstall-service.js" (
    pushd "%INSTALL_DIR%"
    "C:\Program Files\nodejs\node.exe" service\uninstall-service.js >nul 2>&1
    popd
    timeout /t 3 /nobreak >nul
  )
  sc delete "%SERVICE_NAME%" >nul 2>&1
)

REM --- 3. Copy the agent ---
echo [3/4] Copying agent to %INSTALL_DIR% ...
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%"
xcopy /E /I /Y "%SOURCE%agent\*" "%INSTALL_DIR%\" >nul || ( echo [ERR] Copy failed.& exit /b 4 )

if not exist "%DATA_DIR%\spool" mkdir "%DATA_DIR%\spool"
icacls "%INSTALL_DIR%" /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "Users:(OI)(CI)RX" /T >nul
icacls "%DATA_DIR%"    /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" /T >nul

REM --- 4. Register and start the service via node-windows ---
echo [4/4] Registering Windows service...
pushd "%INSTALL_DIR%"
"C:\Program Files\nodejs\node.exe" service\install-service.js
popd
timeout /t 5 /nobreak >nul
sc start "%SERVICE_NAME%" >nul 2>&1

sc query "%SERVICE_NAME%" | findstr /C:"STATE"
echo.
echo Done. Logs: %DATA_DIR%\agent.log
endlocal
exit /b 0
