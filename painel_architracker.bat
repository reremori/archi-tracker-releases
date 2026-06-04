@echo off
setlocal enabledelayedexpansion

:MENU

:: Verificar status do tracker
if exist "C:\tracker-arquitetura\tracker.running" (set STATUS=Rodando) else (set STATUS=Parado)

:: Ler versao instalada
set VER_LOCAL=desconhecida
if exist "C:\tracker-arquitetura\version.txt" (
    set /p VER_LOCAL=<"C:\tracker-arquitetura\version.txt"
)

:: Ler versao disponivel no GitHub
powershell -NoProfile -Command "try { (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/version.txt' -UseBasicParsing).Content.Trim() } catch { 'sem conexao' }" > "C:\tracker-arquitetura\tmp_ver.txt" 2>nul
set /p VER_REMOTE=<"C:\tracker-arquitetura\tmp_ver.txt"
del "C:\tracker-arquitetura\tmp_ver.txt" >nul 2>&1

:: Montar linha de versao
if "%VER_REMOTE%"=="sem conexao" (
    set VER_INFO=Versao instalada: %VER_LOCAL%  ^|  Disponivel: sem conexao
) else if "%VER_LOCAL%"=="%VER_REMOTE%" (
    set VER_INFO=Versao instalada: %VER_LOCAL%  ^|  Disponivel: %VER_REMOTE%  ^(em dia^)
) else (
    set VER_INFO=Versao instalada: %VER_LOCAL%  ^|  Disponivel: %VER_REMOTE%  ^(!^)
)

:: Exibir menu via PowerShell
for /f "delims=" %%i in ('powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.Windows.Forms; " ^
    "Add-Type -AssemblyName System.Drawing; " ^
    "[System.Windows.Forms.Application]::EnableVisualStyles(); " ^
    "$form = New-Object System.Windows.Forms.Form; " ^
    "$form.Text = 'ArchiTracker - Painel de Controle'; " ^
    "$form.Size = New-Object System.Drawing.Size(380, 380); " ^
    "$form.StartPosition = 'CenterScreen'; " ^
    "$form.FormBorderStyle = 'FixedDialog'; " ^
    "$form.MaximizeBox = $false; " ^
    "$lbl1 = New-Object System.Windows.Forms.Label; " ^
    "$lbl1.Text = 'Status: %STATUS%'; " ^
    "$lbl1.Location = New-Object System.Drawing.Point(20, 15); " ^
    "$lbl1.Size = New-Object System.Drawing.Size(330, 20); " ^
    "$lbl1.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); " ^
    "$form.Controls.Add($lbl1); " ^
    "$lbl2 = New-Object System.Windows.Forms.Label; " ^
    "$lbl2.Text = '%VER_INFO%'; " ^
    "$lbl2.Location = New-Object System.Drawing.Point(20, 38); " ^
    "$lbl2.Size = New-Object System.Drawing.Size(330, 20); " ^
    "$lbl2.Font = New-Object System.Drawing.Font('Segoe UI', 8); " ^
    "$form.Controls.Add($lbl2); " ^
    "$buttons = @('Atualizar Tracker', 'Reiniciar Tracker', 'Ver Status', 'Desinstalar', 'Fechar'); " ^
    "$y = 70; " ^
    "foreach ($btn_text in $buttons) { " ^
    "    $btn = New-Object System.Windows.Forms.Button; " ^
    "    $btn.Text = $btn_text; " ^
    "    $btn.Location = New-Object System.Drawing.Point(20, $y); " ^
    "    $btn.Size = New-Object System.Drawing.Size(320, 38); " ^
    "    $btn.Add_Click({ $form.Tag = $this.Text; $form.Close() }); " ^
    "    $form.Controls.Add($btn); " ^
    "    $y += 50 " ^
    "}; " ^
    "$form.ShowDialog() | Out-Null; " ^
    "Write-Output $form.Tag" ^
') do set CHOICE=%%i

if "%CHOICE%"=="Atualizar Tracker" goto ATUALIZAR
if "%CHOICE%"=="Reiniciar Tracker" goto REINICIAR
if "%CHOICE%"=="Ver Status" goto STATUS
if "%CHOICE%"=="Desinstalar" goto DESINSTALAR
if "%CHOICE%"=="Fechar" goto FIM
goto FIM

:: ================================================
:ATUALIZAR
schtasks /end /tn "ArchiTracker" >nul 2>&1
schtasks /end /tn "ArchiTrackerWatchdog" >nul 2>&1
powershell -NoProfile -Command "Get-WmiObject Win32_Process -Filter 'name=''python.exe''' | Where-Object { $_.CommandLine -like '*tracker-arquitetura*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
taskkill /f /im wscript.exe >nul 2>&1
timeout /t 3 /nobreak >nul

powershell -NoProfile -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/corrigir_architracker.bat','C:\tracker-arquitetura\corrigir_architracker.bat')"

cmd /c "C:\tracker-arquitetura\corrigir_architracker.bat"
goto MENU

:: ================================================
:REINICIAR
schtasks /end /tn "ArchiTracker" >nul 2>&1
schtasks /end /tn "ArchiTrackerWatchdog" >nul 2>&1
powershell -NoProfile -Command "Get-WmiObject Win32_Process -Filter 'name=''python.exe''' | Where-Object { $_.CommandLine -like '*tracker-arquitetura*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
taskkill /f /im wscript.exe >nul 2>&1
timeout /t 4 /nobreak >nul
schtasks /run /tn "ArchiTracker" >nul 2>&1
powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.Windows.Forms; " ^
    "[System.Windows.Forms.MessageBox]::Show('Tracker reiniciado!', 'ArchiTracker', 'OK', 'Information')" >nul 2>&1
goto MENU

:: ================================================
:STATUS
if exist "C:\tracker-arquitetura\tracker.running" (
    set MSG=Tracker esta RODANDO.
) else (
    set MSG=Tracker esta PARADO.
)
powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.Windows.Forms; " ^
    "[System.Windows.Forms.MessageBox]::Show('%MSG%', 'ArchiTracker - Status', 'OK', 'Information')" >nul 2>&1
goto MENU

:: ================================================
:DESINSTALAR
powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.Windows.Forms; " ^
    "$r = [System.Windows.Forms.MessageBox]::Show('Isso vai remover o ArchiTracker desta maquina. Os dados no Supabase nao serao apagados. Deseja continuar?', 'ArchiTracker - Desinstalar', 'YesNo', 'Warning'); " ^
    "Write-Output $r" > "C:\tracker-arquitetura\tmp_confirm.txt"

set /p CONFIRM=<"C:\tracker-arquitetura\tmp_confirm.txt"
del "C:\tracker-arquitetura\tmp_confirm.txt" >nul 2>&1

if /i "%CONFIRM%"=="Yes" (
    schtasks /end /tn "ArchiTracker" >nul 2>&1
    schtasks /end /tn "ArchiTrackerWatchdog" >nul 2>&1
    timeout /t 3 /nobreak >nul
    taskkill /f /im python.exe >nul 2>&1
    taskkill /f /im pythonw.exe >nul 2>&1
    taskkill /f /im wscript.exe >nul 2>&1
    timeout /t 3 /nobreak >nul
    schtasks /delete /tn "ArchiTracker" /f >nul 2>&1
    schtasks /delete /tn "ArchiTrackerWatchdog" /f >nul 2>&1
    timeout /t 2 /nobreak >nul
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -Path 'C:\tracker-arquitetura' -Recurse -Force -ErrorAction SilentlyContinue"
    timeout /t 2 /nobreak >nul
    if exist "C:\tracker-arquitetura" rd /s /q "C:\tracker-arquitetura" >nul 2>&1
    if exist "%PUBLIC%\Desktop\ArchiTracker.lnk" del /f /q "%PUBLIC%\Desktop\ArchiTracker.lnk" >nul 2>&1
    if exist "%USERPROFILE%\Desktop\ArchiTracker.lnk" del /f /q "%USERPROFILE%\Desktop\ArchiTracker.lnk" >nul 2>&1
    powershell -NoProfile -Command ^
        "Add-Type -AssemblyName System.Windows.Forms; " ^
        "[System.Windows.Forms.MessageBox]::Show('ArchiTracker removido com sucesso!', 'ArchiTracker', 'OK', 'Information')" >nul 2>&1
    goto FIM
) else (
    goto MENU
)

:: ================================================
:FIM
endlocal
