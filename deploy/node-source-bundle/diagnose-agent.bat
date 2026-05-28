@echo off
REM ============================================================================
REM  UAM Agent Diagnostic — run on any client machine to check why the agent
REM  isn't reporting to the backend. Read the output top-to-bottom; the first
REM  red flag is usually the root cause.
REM
REM  Push to a problem machine and run as Administrator:
REM     diagnose-agent.bat > C:\temp\agent-diag.log 2>&1
REM     type C:\temp\agent-diag.log
REM ============================================================================
setlocal

set "INSTALL_DIR=C:\Program Files\UAMAgent"
set "DATA_DIR=C:\ProgramData\UAMAgent"
set "ALT_INSTALL=C:\ProgramData\UAMAgent\uam-agent"
set "TASK_NAME=UAMAgent"

echo === UAM Agent Diagnostic - %DATE% %TIME% ===
echo Machine: %COMPUTERNAME%
echo User:    %USERDOMAIN%\%USERNAME%
echo.

REM --- 1. Is the scheduled task registered? ---
echo [1/8] Scheduled task status
schtasks /Query /TN "%TASK_NAME%" /V /FO LIST 2>nul | findstr /i "TaskName Status Last Result Run Next User"
if errorlevel 1 (
  echo   [WARN] Scheduled task "%TASK_NAME%" not found.
  echo   The agent has never been installed via install-as-task.bat, OR was uninstalled.
)
echo.

REM --- 2. Is an agent process actually running? ---
echo [2/8] Running agent processes (node.exe / uam-agent.exe / wscript.exe with UAMAgent)
tasklist /FI "IMAGENAME eq node.exe"      /v /fo list 2>nul | findstr /i "UAMAgent" >nul && tasklist /FI "IMAGENAME eq node.exe"      /v /fo list | findstr /i "Image Name Session User"
tasklist /FI "IMAGENAME eq uam-agent.exe" /v /fo list 2>nul | findstr /i "uam-agent" >nul && tasklist /FI "IMAGENAME eq uam-agent.exe" /v /fo list | findstr /i "Image Name Session User"
echo.

REM --- 3. Are the agent files where we expect them? ---
echo [3/8] Install location
if exist "%INSTALL_DIR%\src\index.js" (
  echo   Found source-based install: %INSTALL_DIR%
) else if exist "%INSTALL_DIR%\uam-agent.exe" (
  echo   Found EXE install: %INSTALL_DIR%
) else if exist "%ALT_INSTALL%\uam-agent.exe" (
  echo   Found legacy EXE install: %ALT_INSTALL%
) else (
  echo   [WARN] No agent install found in any known location.
)
echo.

REM --- 4. Config — what API URL is the agent using? ---
echo [4/8] Agent config (apiBaseUrl)
if exist "%INSTALL_DIR%\config.json" (
  type "%INSTALL_DIR%\config.json" | findstr /i "apiBaseUrl agentKey"
) else if exist "%ALT_INSTALL%\config.json" (
  type "%ALT_INSTALL%\config.json" | findstr /i "apiBaseUrl agentKey"
) else (
  echo   [WARN] No config.json found.
)
echo.

REM --- 5. Recent agent log ---
echo [5/8] Last 20 lines of agent.log
if exist "%DATA_DIR%\agent.log" (
  powershell -NoProfile -Command "Get-Content '%DATA_DIR%\agent.log' -Tail 20"
) else (
  echo   [WARN] %DATA_DIR%\agent.log does not exist.
)
echo.

REM --- 6. Spool directory: stuck batches mean network/API failure ---
echo [6/8] Spool directory contents (stuck batches = failed sends)
if exist "%DATA_DIR%\spool" (
  dir /b "%DATA_DIR%\spool\*.json" 2>nul | find /c /v "" > "%TEMP%\_uam_spool_count.txt"
  set /p SPOOL_COUNT=<"%TEMP%\_uam_spool_count.txt"
  del "%TEMP%\_uam_spool_count.txt" 2>nul
  echo   Spool file count: %SPOOL_COUNT%
  if not "%SPOOL_COUNT%"=="0" (
    echo   [INFO] Stuck batches indicate the agent cannot reach the API server.
    dir "%DATA_DIR%\spool\*.json" 2>nul
  )
) else (
  echo   [WARN] Spool directory missing.
)
echo.

REM --- 7. Network reachability to the backend ---
echo [7/8] Backend reachability
for /f "tokens=2 delims=:," %%U in ('findstr /i "apiBaseUrl" "%INSTALL_DIR%\config.json" 2^>nul') do (
  set "API_URL=%%~U"
)
if not defined API_URL (
  for /f "tokens=2 delims=:," %%U in ('findstr /i "apiBaseUrl" "%ALT_INSTALL%\config.json" 2^>nul') do (
    set "API_URL=%%~U"
  )
)
if defined API_URL (
  REM Strip leading space and quotes
  set "API_URL=%API_URL: =%"
  set "API_URL=%API_URL:"=%"
  echo   API URL from config: %API_URL%
  echo   Attempting GET %API_URL%/health ...
  powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri '%API_URL%/health' -UseBasicParsing -TimeoutSec 10; Write-Host ('   HTTP ' + $r.StatusCode + ' - ' + $r.Content.Substring(0, [Math]::Min(200, $r.Content.Length))) } catch { Write-Host ('   [ERR] ' + $_.Exception.Message) }"
) else (
  echo   [WARN] Could not read API URL from config.
)
echo.

REM --- 8. Windows Defender / EDR exclusions ---
echo [8/8] Defender exclusions for UAMAgent
powershell -NoProfile -Command "try { (Get-MpPreference).ExclusionPath | Where-Object { $_ -like '*UAMAgent*' } | ForEach-Object { Write-Host ('   ' + $_) } } catch { Write-Host '   (Defender query failed or not present)' }"
echo.

echo === Diagnostic complete ===
echo.
echo Common diagnoses based on the output above:
echo   - Section [1] empty / 'not found'   -^> Agent not installed. Run install-as-task.bat.
echo   - Section [2] empty                 -^> Agent crashed or task never fired.
echo                                          Try: schtasks /Run /TN UAMAgent
echo   - Section [5] shows 'sync failed'   -^> Network/API issue. See [7].
echo   - Section [6] has stuck batches     -^> API unreachable for a while.
echo   - Section [7] 'HTTP 200'            -^> Network OK; agent has another problem.
echo   - Section [7] 'connection refused'  -^> Backend down or firewall blocking.
echo   - Section [7] 'name resolution'     -^> DNS issue resolving build.mahathiinfotech.com.
echo.
endlocal
