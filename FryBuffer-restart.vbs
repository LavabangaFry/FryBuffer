' Restart: waits until the previous instance exits, then starts a fresh one.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
base = fso.GetParentFolderName(WScript.ScriptFullName)
WScript.Sleep 1500
sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & base & "\FryBuffer.ps1""", 0, False
