' FryBuffer launcher: no console window, paths resolved from the script folder.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
base = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & base & "\FryBuffer.ps1""", 0, False
