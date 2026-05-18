@echo off
REM ============================================================================
REM  UAM Activity Agent - Node 22 SEA (Single Executable Applications) build
REM
REM  Why SEA over pkg:
REM    - SEA copies the official signed node.exe and embeds your script in it.
REM    - The exe inherits Node.js's OpenJS Foundation Authenticode signature
REM      (until you modify it), so Defender does not flag it.
REM    - No 'pkg-cache', no Brotli, no fabricator step — fewer AV trip wires.
REM
REM  Requirements on the build machine:
REM    - Node.js 22 LTS installed (uses node.exe in-place from the user's PATH).
REM    - npm install esbuild --save-dev    (for bundling)
REM    - npm install --save-dev postject    (for embedding the resource)
REM
REM  Output:
REM    release\uam-agent.exe   - your agent, ~80 MB, behaves like pkg output
REM ============================================================================
setlocal

set "ROOT=%~dp0"
set "RELEASE=%ROOT%release"
set "BUNDLE=%ROOT%dist\bundle.js"
set "SEA_BLOB=%ROOT%dist\sea.blob"
set "SEA_CFG=%ROOT%dist\sea-config.json"
set "EXE_OUT=%RELEASE%\uam-agent.exe"

if exist "%RELEASE%" rmdir /s /q "%RELEASE%"
if not exist "%ROOT%dist" mkdir "%ROOT%dist"
mkdir "%RELEASE%"

REM --- 1. Install build helpers (idempotent) ---------------------------------
echo [1/6] Installing build helpers (esbuild, postject)...
call npm install --save-dev esbuild postject --no-audit --no-fund || goto :fail

REM --- 2. Bundle the agent into a single .js file ----------------------------
echo [2/6] Bundling source with esbuild...
call node_modules\.bin\esbuild src\index.js --bundle --platform=node --target=node20 --outfile="%BUNDLE%" --external:node-windows || goto :fail

REM --- 3. Write SEA config ---------------------------------------------------
echo [3/6] Writing SEA config...
> "%SEA_CFG%" echo {
>>"%SEA_CFG%" echo   "main": "dist/bundle.js",
>>"%SEA_CFG%" echo   "output": "dist/sea.blob",
>>"%SEA_CFG%" echo   "disableExperimentalSEAWarning": true,
>>"%SEA_CFG%" echo   "useSnapshot": false,
>>"%SEA_CFG%" echo   "useCodeCache": true,
>>"%SEA_CFG%" echo   "assets": {
>>"%SEA_CFG%" echo     "probe.ps1": "src/ps/probe.ps1"
>>"%SEA_CFG%" echo   }
>>"%SEA_CFG%" echo }

REM --- 4. Generate SEA blob --------------------------------------------------
echo [4/6] Generating SEA blob...
node --experimental-sea-config "%SEA_CFG%" || goto :fail

REM --- 5. Copy the official node.exe and inject the blob ---------------------
echo [5/6] Copying signed node.exe and injecting blob...
for /f "tokens=*" %%i in ('where node.exe') do set "NODE_EXE=%%i"
if not defined NODE_EXE goto :fail
copy /Y "%NODE_EXE%" "%EXE_OUT%" >nul

REM Remove the existing OpenJS signature first (postject can't inject into a signed binary)
REM We'll re-sign at the end if a cert is provided. If you don't sign, the exe
REM is unsigned but still uses the official node binary contents.
where signtool >nul 2>&1
if not errorlevel 1 (
  signtool remove /s "%EXE_OUT%" >nul 2>&1
)

REM Inject the SEA blob using postject
node --experimental-sea-config "%SEA_CFG%" >nul
call node_modules\.bin\postject "%EXE_OUT%" NODE_SEA_BLOB "%SEA_BLOB%" --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2 --overwrite || goto :fail

REM --- 6. Stamp metadata + (optional) sign + assemble release folder ---------
echo [6/6] Finalizing...
where rcedit >nul 2>&1
if not errorlevel 1 (
  rcedit "%EXE_OUT%" --set-version-string "ProductName" "UAM Activity Agent"     --set-version-string "CompanyName" "Mahathi Infotech"     --set-version-string "FileDescription" "User Activity Monitoring Agent"     --set-file-version "1.0.0.0" --set-product-version "1.0.0.0"
)

if defined SIGN_CERT_PFX (
  signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f "%SIGN_CERT_PFX%" /p "%SIGN_CERT_PASS%" "%EXE_OUT%"
  signtool verify /pa "%EXE_OUT%"
) else (
  echo   ^(SIGN_CERT_PFX not set; producing unsigned exe.^)
)

copy /Y "%ROOT%config.json"                "%RELEASE%\config.json" >nul
if exist "%ROOT%..\deploy\bundle\install.bat"   copy /Y "%ROOT%..\deploy\bundle\install.bat"   "%RELEASE%\install.bat"   >nul
if exist "%ROOT%..\deploy\bundle\uninstall.bat" copy /Y "%ROOT%..\deploy\bundle\uninstall.bat" "%RELEASE%\uninstall.bat" >nul
certutil -hashfile "%EXE_OUT%" SHA256 > "%RELEASE%\BUILD-INFO.txt"

echo.
echo ============================================================================
echo  SEA BUILD OK
echo  Output:   %EXE_OUT%
echo  Release:  %RELEASE%\
echo ============================================================================
endlocal
exit /b 0

:fail
echo BUILD FAILED.
endlocal
exit /b 1
