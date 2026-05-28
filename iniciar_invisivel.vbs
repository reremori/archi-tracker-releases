Dim fso
Set fso = CreateObject("Scripting.FileSystemObject")
If fso.FileExists("C:\tracker-arquitetura\tracker.lock") Then
    fso.DeleteFile "C:\tracker-arquitetura\tracker.lock"
End If
CreateObject("WScript.Shell").Run "C:\tracker-arquitetura\venv\Scripts\python.exe C:\tracker-arquitetura\api.py", 0, False
