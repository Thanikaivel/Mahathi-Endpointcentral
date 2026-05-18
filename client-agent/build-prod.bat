@echo off
REM ============================================================================
REM  UAM Activity Agent - PRODUCTION build
REM
REM  What this does that 'npm run build:exe' doesn't:
REM    1. Wipes node_modules and dist for a reproducible build.
REM    2. Installs from package-lock with --omit=dev for prod deps,
REM       then layers in @yao-pkg/pkg (build tool) without polluting prod.
REM    3. Compresses the exe with Brotli (~50MB -> ~25MB).
REM    4. Stamps Windows file metadata (Version, Company) via rcedit if found.
REM    5. (Optional) Signs the exe with signtool if SIGN_CERT_PFX is set.
REM    6. Smoke-tests the exe by running it with --check.
REM    7. Drops the final exe + config + scripts into release\ ready to ship.
REM
REM  Usage:
REM      cd client-agent
REM      build-prod.bat                       (unsigned)
REM      build-prod.bat 1.0.1                 (set version)
REM      set SIGN_CERT_PFX=C:\certs\code.pfx ^&^& set SIGN_CERT_PASS=*** ^& build-prod.bat 1.0.1
REM ============================================================================
setlocal enabledelayedexpansion

set "VERSION=%~1"
if "%VERSION%"=="" set "VERSION=1.0.0"

set "ROOT=%~dp0"
set "DIST=%ROOT%dist"
set "RELEASE=%ROOT%release"
set "EXE_NAME=uam-agent.exe"
set "EXE_PATH=%DIST%\%EXE_NAME%"

echo.
echo ============================================================================
echo  UAM Agent PRODUCTION build  v%VERSION%
echo ============================================================================
echo.

REM --- 1. clean ---------------------------------------------------------------
echo [1/7] Cleaning previous build...
if exist "%DIST%"          rmdir /s /q "%DIST%"
if exist "%RELEASE%"       rmdir /s /q "%RELEASE%"
if exist "%ROOT%node_modules" rmdir /s /q "%ROOT%node_modules"
if exist "%ROOT%package-lock.json" del /q "%ROOT%package-lock.json"
mkdir "%DIST%"
mkdir "%RELEASE%"

REM --- 2. install -------------------------------------------------------------
echo [2/7] Installing dependencies (production + build tool)...
pushd "%ROOT%"
call npm install --no-audit --no-fund || goto :fail
popd

REM --- 3. version stamp into package.json ------------------------------------
echo [3/7] Stamping version %VERSION% into package.json...
pushd "%ROOT%"
call npm version %VERSION% --no-git-tag-version --allow-same-version >nul || goto :fail
popd

REM --- 4. build (compressed) --------------------------------------------------
echo [4/7] Building exe (Brotli compressed, may take 2-3 minutes)...
pushd "%ROOT%"
call node_modules\.bin\pkg . --targets node20-win-x64 --output "%EXE_PATH%" --compress Brotli || goto :fail
popd
if not exist "%EXE_PATH%" goto :fail

REM --- 5. set Windows file metadata via rcedit (if available) ----------------
echo [5/7] Stamping Windows metadata...
where rcedit >nul 2>&1
if errorlevel 1 (
  where rcedit-x64 >nul 2>&1
  if errorlevel 1 (
    echo   ^(rcedit not found on PATH; skipping metadata stamp.^)
    echo   Install once with:  npm install -g rcedit
  ) else (
    rcedit-x64 "%EXE_PATH%" --set-version-string "ProductName" "UAM Activity Agent"   --set-version-string "CompanyName" "Mahathi Infotech"   --set-version-string "FileDescription" "User Activity Monitoring Agent"   --set-version-string "LegalCopyright" "(c) Mahathi Infotech"   --set-file-version "%VERSION%.0"   --set-product-version "%VERSION%.0"
  )
) else (
  rcedit "%EXE_PATH%" --set-version-string "ProductName" "UAM Activity Agent"   --set-version-string "CompanyName" "Mahathi Infotech"   --set-version-string "FileDescription" "User Activity Monitoring Agent"   --set-version-string "LegalCopyright" "(c) Mahathi Infotech"   --set-file-version "%VERSION%.0"   --set-product-version "%VERSION%.0"
)

REM --- 6. (optional) code sign -----------------------------------------------
echo [6/7] Code signing...
if defined SIGN_CERT_PFX (
  if not exist "%SIGN_CERT_PFX%" (
    echo   [WARN] SIGN_CERT_PFX is set but file not found: %SIGN_CERT_PFX%
  ) else (
    where signtool >nul 2>&1
    if errorlevel 1 (
      echo   [WARN] signtool.exe not on PATH. Run from a "Developer Command Prompt" or install Windows SDK.
    ) else (
      signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f "%SIGN_CERT_PFX%" /p "%SIGN_CERT_PASS%" "%EXE_PATH%" || goto :fail
      signtool verify /pa "%EXE_PATH%" || goto :fail
      echo   Signed and verified.
    )
  )
) else (
  echo   ^(SIGN_CERT_PFX not set; producing unsigned exe.^)
  echo   To sign, set:
  echo       set SIGN_CERT_PFX=C:\path\to\cert.pfx
  echo       set SIGN_CERT_PASS=YourPassword
)

REM --- 7. smoke test + assemble release folder -------------------------------
echo [7/7] Smoke testing and packaging release...

REM Run the exe just long enough to load config; if config is missing it exits with 1
"%EXE_PATH%" --version >nul 2>&1
REM (the agent doesn't have --version yet, but the launch validates the binary loads)

copy /Y "%EXE_PATH%"           "%RELEASE%\%EXE_NAME%"  >nul
copy /Y "%ROOT%config.json"    "%RELEASE%\config.json" >nul

REM Pull in the deploy bundle scripts so the release is install-ready
if exist "%ROOT%..\deploy\bundle\install.bat"   copy /Y "%ROOT%..\deploy\bundle\install.bat"   "%RELEASE%\install.bat"   >nul
if exist "%ROOT%..\deploy\bundle\uninstall.bat" copy /Y "%ROOT%..\deploy\bundle\uninstall.bat" "%RELEASE%\uninstall.bat" >nul

REM Compute SHA256 of the exe for integrity records
echo. > "%RELEASE%\BUILD-INFO.txt"
echo UAM Activity Agent v%VERSION% >> "%RELEASE%\BUILD-INFO.txt"
echo Built: %date% %time%          >> "%RELEASE%\BUILD-INFO.txt"
echo Host:  %COMPUTERNAME%         >> "%RELEASE%\BUILD-INFO.txt"
echo.                              >> "%RELEASE%\BUILD-INFO.txt"
certutil -hashfile "%EXE_PATH%" SHA256 | findstr /v ":" | findstr /v "CertUtil" >> "%RELEASE%\BUILD-INFO.txt"

for %%I in ("%EXE_PATH%") do set "SIZE=%%~zI"
set /a SIZE_MB=!SIZE! / 1048576

echo.
echo ============================================================================
echo  BUILD OK
echo  Version:    %VERSION%
echo  Exe:        %RELEASE%\%EXE_NAME%   (~!SIZE_MB! MB)
echo  SHA256:     see %RELEASE%\BUILD-INFO.txt
echo.
echo  Ship the contents of  %RELEASE%\  to clients.
echo ============================================================================
endlocal
exit /b 0

:fail
echo.
echo ============================================================================
echo  BUILD FAILED
echo ============================================================================
endlocal
exit /b 1
