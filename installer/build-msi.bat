@echo off
REM ============================================================================
REM  Build UAMAgent.msi from UAMAgent.wxs using WiX Toolset 3.x.
REM
REM  ONE-TIME PREP on the build machine:
REM    1. Install WiX Toolset 3.14 from https://wixtoolset.org/releases/
REM       (adds candle.exe, light.exe, heat.exe to %PATH%).
REM    2. Download WinSW (net4 build, signed):
REM       https://github.com/winsw/winsw/releases  ->  WinSW-x64.exe
REM       Save it as:  installer\staging\winsw\uam-agent-service.exe
REM    3. (Optional) Drop an icon at:  installer\staging\uam.ico
REM
REM  REPEAT before each release:
REM    Run build-msi.bat from the installer\ folder.
REM    Output:  installer\out\UAMAgent.msi
REM ============================================================================
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "STAGING=%ROOT%staging"
set "AGENT_SRC=%STAGING%\agent"
set "OUT=%ROOT%out"
set "WIX=%WIX%"
if "%WIX%"=="" set "WIX=C:\Program Files (x86)\WiX Toolset v3.14\bin"

if not exist "%STAGING%\winsw\uam-agent-service.exe" (
  echo [ERR] WinSW not found at:
  echo       %STAGING%\winsw\uam-agent-service.exe
  echo Download WinSW-x64.exe from https://github.com/winsw/winsw/releases
  echo and copy it to that path renamed as uam-agent-service.exe
  exit /b 1
)
if not exist "%STAGING%\uam.ico" (
  echo Creating placeholder icon...
  powershell -NoProfile -Command "$null = New-Item -Type File -Force '%STAGING%\uam.ico'"
)

REM --- 1. Stage agent source ----------------------------------------------------
echo [1/4] Staging agent source...
if exist "%AGENT_SRC%" rmdir /s /q "%AGENT_SRC%"
mkdir "%AGENT_SRC%"
xcopy /Y    "%ROOT%..\client-agent\package.json"  "%AGENT_SRC%\" >nul
xcopy /Y    "%ROOT%..\client-agent\config.json"   "%AGENT_SRC%\" >nul
xcopy /E /I /Y "%ROOT%..\client-agent\src"        "%AGENT_SRC%\src" >nul

echo Installing production dependencies into staging...
pushd "%AGENT_SRC%"
call npm install --omit=dev --no-audit --no-fund --no-package-lock || ( popd & exit /b 2 )
popd

REM --- 2. Heat-harvest the agent folder into a ComponentGroup ------------------
echo [2/4] Harvesting agent files via heat...
"%WIX%\heat.exe" dir "%AGENT_SRC%" -nologo -ag -srd -sreg -sfrag -scom -gg -cg AgentFiles -dr INSTALLFOLDER -var var.AgentSrc -out "%ROOT%AgentFiles.wxs" || exit /b 3

REM --- 3. Compile + link --------------------------------------------------------
echo [3/4] Compiling...
if not exist "%OUT%" mkdir "%OUT%"
"%WIX%\candle.exe" -nologo -ext WixUtilExtension -dAgentSrc="%AGENT_SRC%" -arch x64 -out "%OUT%\\" "%ROOT%UAMAgent.wxs" "%ROOT%AgentFiles.wxs" || exit /b 4

echo [4/4] Linking MSI...
"%WIX%\light.exe" -nologo -ext WixUtilExtension -spdb -b "%STAGING%" -out "%OUT%\UAMAgent.msi" "%OUT%\UAMAgent.wixobj" "%OUT%\AgentFiles.wixobj" || exit /b 5

REM --- 4. (Optional) sign --------------------------------------------------------
if defined SIGN_CERT_PFX (
  echo Signing MSI...
  signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f "%SIGN_CERT_PFX%" /p "%SIGN_CERT_PASS%" "%OUT%\UAMAgent.msi" || exit /b 6
)

certutil -hashfile "%OUT%\UAMAgent.msi" SHA256
echo.
echo ============================================================================
echo  BUILT: %OUT%\UAMAgent.msi
echo ============================================================================
endlocal
exit /b 0
