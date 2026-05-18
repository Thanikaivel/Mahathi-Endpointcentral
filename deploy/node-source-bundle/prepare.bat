@echo off
REM ============================================================================
REM  Run this on the build/dev machine to assemble the deployable bundle.
REM  Output:
REM     deploy\node-source-bundle\
REM         install.bat
REM         uninstall.bat
REM         node-v20.18.0-x64.msi    (you download this once)
REM         agent\                   (copy of client-agent with prod deps)
REM ============================================================================
setlocal
set "ROOT=%~dp0"
set "SRC=%ROOT%..\..\client-agent"
set "DST=%ROOT%agent"

if not exist "%SRC%" ( echo [ERR] %SRC% not found.& exit /b 1 )

if not exist "%ROOT%node-v20.18.0-x64.msi" (
  echo.
  echo Download Node.js LTS first:
  echo    https://nodejs.org/dist/v20.18.0/node-v20.18.0-x64.msi
  echo Save it as: %ROOT%node-v20.18.0-x64.msi
  echo.
  exit /b 2
)

echo Cleaning old bundle...
if exist "%DST%" rmdir /s /q "%DST%"
mkdir "%DST%"

echo Copying agent source...
xcopy /Y    "%SRC%\package.json"      "%DST%\" >nul
xcopy /Y    "%SRC%\package-lock.json" "%DST%\" >nul 2>&1
xcopy /Y    "%SRC%\config.json"       "%DST%\" >nul
xcopy /E /I /Y "%SRC%\src"            "%DST%\src"     >nul
xcopy /E /I /Y "%SRC%\service"        "%DST%\service" >nul

echo Installing production dependencies into bundle...
pushd "%DST%"
call npm install --omit=dev --no-audit --no-fund --no-package-lock || ( popd & exit /b 3 )
REM node-windows MUST be present for service registration
call npm install node-windows --no-audit --no-fund --no-package-lock || ( popd & exit /b 4 )
popd

echo.
echo Bundle ready in:  %ROOT%
echo You can now copy the entire 'node-source-bundle' folder to a client and run install.bat.
endlocal
