$procs = Get-WmiObject Win32_Process -Filter "name='python.exe'" | Where-Object { $_.CommandLine -like '*tracker-arquitetura*' }
$count = ($procs | Measure-Object).Count
if ($count -eq 0) {
    Start-Process wscript.exe -ArgumentList "C:\tracker-arquitetura\iniciar_invisivel.vbs" -WindowStyle Hidden
} elseif ($count -gt 1) {
    $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-Sleep 3
    Start-Process wscript.exe -ArgumentList "C:\tracker-arquitetura\iniciar_invisivel.vbs" -WindowStyle Hidden
}
