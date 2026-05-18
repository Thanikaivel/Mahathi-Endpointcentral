' Run install-as-task.bat completely hidden (no console window).
' Usage:   wscript install-silent.vbs
' Or double-click the .vbs file (must already be elevated for full install).
'
' Returns exit code from install-as-task.bat. Log to a file so you can verify
' success without a visible window.

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Resolve folder this VBS lives in
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
batPath   = scriptDir & "\install-as-task.bat"
logPath   = scriptDir & "\install-silent.log"

If Not fso.FileExists(batPath) Then
    WScript.Echo "install-as-task.bat not found next to this script."
    WScript.Quit 1
End If

' Run install-as-task.bat hidden, redirect output to log, wait for finish.
'   0 = hidden window
'   True = wait for completion
cmdLine = "cmd /c """"" & batPath & """ > """ & logPath & """ 2>&1"""
rc = WshShell.Run(cmdLine, 0, True)
WScript.Quit rc
