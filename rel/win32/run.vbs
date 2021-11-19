' This avoids a flashing cmd window when launching the bat file
strPath = Left(Wscript.ScriptFullName, Len(Wscript.ScriptFullName) - Len(Wscript.ScriptName)) & "run.bat"
' Debug: MsgBox(strPath)

Dim Args()
ReDim Args(WScript.Arguments.Count - 1)

For i = 0 To WScript.Arguments.Count - 1
   Args(i) = """" & WScript.Arguments(i) & """"
Next

Set WshShell = CreateObject("WScript.Shell" )
WshShell.Run """" & strPath & """ start -- " & Join(Args), 0
Set WshShell = Nothing