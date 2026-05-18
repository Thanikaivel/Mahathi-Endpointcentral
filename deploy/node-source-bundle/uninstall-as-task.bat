@echo off
REM Removes the Scheduled-Task version of the agent.
setlocal
set "INSTALL_DIR=C:\Program Files\UAMAgent"
set "TASK_NAME=UAMAgent"

net session >nul 2>&1
if errorlevel 1 ( echo Run as Administrator. & exit /b 1 )

echo Stopping & deleting scheduled task...
schtasks /End    /TN "%TASK_NAME%" >nul 2>&1
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1

REM Best-effort: also kill any running agent processes (per logged-in user)
echo Killing any running node.exe agent processes...
for /f "tokens=2 delims=," %%P in ('tasklist /v /fo csv /nh ^| findstr /i "UAMAgent\\src\\index.js"') do (
  taskkill /F /PID %%~P >nul 2>&1
)

echo Removing %INSTALL_DIR%...
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"

echo Done. ProgramData kept at C:\ProgramData\UAMAgent (delete manually if desired).
endlocal
exit /b 0
