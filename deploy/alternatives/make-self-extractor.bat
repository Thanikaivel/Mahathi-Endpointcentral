@echo off
REM ============================================================================
REM  Build a single-file self-extracting installer using IExpress (built into
REM  Windows, no third-party tool required).
REM
REM  Output: UAM-Agent-Setup.exe
REM     Double-click and it silently extracts to %TEMP% and runs install.bat
REM     elevated (UAC prompts once).
REM
REM  Run from the deploy\ folder.
REM ============================================================================
setlocal

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-13%"
set "BUNDLE=%ROOT%bundle"
set "OUT=%ROOT%UAM-Agent-Setup.exe"
set "SED=%TEMP%\uam-iexpress.sed"

if not exist "%BUNDLE%\uam-agent.exe" ( echo Build the agent first. & exit /b 1 )

> "%SED%" echo [Version]
>>"%SED%" echo Class=IEXPRESS
>>"%SED%" echo SEDVersion=3
>>"%SED%" echo [Options]
>>"%SED%" echo PackagePurpose=InstallApp
>>"%SED%" echo ShowInstallProgramWindow=0
>>"%SED%" echo HideExtractAnimation=1
>>"%SED%" echo UseLongFileName=1
>>"%SED%" echo InsideCompressed=0
>>"%SED%" echo CAB_FixedSize=0
>>"%SED%" echo CAB_ResvCodeSigning=0
>>"%SED%" echo RebootMode=N
>>"%SED%" echo InstallPrompt=%%InstallPrompt%%
>>"%SED%" echo DisplayLicense=%%DisplayLicense%%
>>"%SED%" echo FinishMessage=%%FinishMessage%%
>>"%SED%" echo TargetName=%OUT%
>>"%SED%" echo FriendlyName=UAM Activity Agent Setup
>>"%SED%" echo AppLaunched=cmd /c install.bat
>>"%SED%" echo PostInstallCmd=^<None^>
>>"%SED%" echo AdminQuietInstCmd=
>>"%SED%" echo UserQuietInstCmd=
>>"%SED%" echo SourceFiles=SourceFiles
>>"%SED%" echo [Strings]
>>"%SED%" echo InstallPrompt=
>>"%SED%" echo DisplayLicense=
>>"%SED%" echo FinishMessage=
>>"%SED%" echo TargetName=%OUT%
>>"%SED%" echo FriendlyName=UAM Activity Agent Setup
>>"%SED%" echo AppLaunched=cmd /c install.bat
>>"%SED%" echo PostInstallCmd=^<None^>
>>"%SED%" echo [SourceFiles]
>>"%SED%" echo SourceFiles0=%BUNDLE%\
>>"%SED%" echo [SourceFiles0]
>>"%SED%" echo %%FILE0%%=
>>"%SED%" echo %%FILE1%%=
>>"%SED%" echo %%FILE2%%=
>>"%SED%" echo [Strings]
>>"%SED%" echo FILE0=install.bat
>>"%SED%" echo FILE1=uam-agent.exe
>>"%SED%" echo FILE2=config.json

iexpress /N /Q "%SED%"

if exist "%OUT%" (
  echo.
  echo Built: %OUT%
  echo Right-click -^> Run as administrator to install on any single machine.
) else (
  echo IExpress failed. Try running it interactively: iexpress /N
)

endlocal
