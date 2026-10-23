' Klik dua kali file ini untuk menjalankan Dynamic Island tanpa jendela hitam.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run """" & dir & "\node_modules\electron\dist\electron.exe"" """ & dir & """", 0, False
