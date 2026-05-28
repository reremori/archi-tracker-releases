@echo off
setlocal enabledelayedexpansion

:MENU

:: Verificar status do tracker
tasklist /fi "imagename eq python.exe" 2>nul | find /i "python.exe" >nul 2>&1
if %errorlevel% equ 0 (
    set STATUS=Rodando
) else (
    set STATUS=Parado
)

:: Ler versao instalada
set VER_LOCAL=desconhecida
if exist "C:\tracker-arquitetura\version.txt" (
    set /p VER_LOCAL=<"C:\tracker-arquitetura\version.txt"
)

:: Ler versao disponivel no GitHub
powershell -NoProfile -Command "try { (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/version.txt' -UseBasicParsing).Content.Trim() } catch { 'sem conexao' }" > "%TEMP%\archi_ver_remote.txt" 2>nul
set /p VER_REMOTE=<"%TEMP%\archi_ver_remote.txt"
del "%TEMP%\archi_ver_remote.txt" >nul 2>&1

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
:: Encerrar tracker
schtasks /end /tn "ArchiTracker" >nul 2>&1
schtasks /end /tn "ArchiTrackerWatchdog" >nul 2>&1
taskkill /f /im python.exe >nul 2>&1
taskkill /f /im wscript.exe >nul 2>&1
timeout /t 3 /nobreak >nul

:: Baixar todos os arquivos
set BASE_URL=https://raw.githubusercontent.com/reremori/archi-tracker-releases/main
set PASTA=C:\tracker-arquitetura
set ERR=0

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%BASE_URL%/api.py' -OutFile '%PASTA%\api.py' -UseBasicParsing -TimeoutSec 30" >nul 2>&1
if %errorlevel% neq 0 set ERR=1

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%BASE_URL%/iniciar_invisivel.vbs' -OutFile '%PASTA%\iniciar_invisivel.vbs' -UseBasicParsing -TimeoutSec 30" >nul 2>&1
if %errorlevel% neq 0 set ERR=1

powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%BASE_URL%/corrigir_architracker.bat' -OutFile '%PASTA%\corrigir_architracker.bat' -UseBasicParsing -TimeoutSec 30" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%BASE_URL%/painel_architracker.bat' -OutFile '%PASTA%\painel_architracker.bat' -UseBasicParsing -TimeoutSec 30" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%BASE_URL%/version.txt' -OutFile '%PASTA%\version.txt' -UseBasicParsing -TimeoutSec 30" >nul 2>&1

if %ERR% equ 0 (
    if exist "%PASTA%\tracker.lock" del /f /q "%PASTA%\tracker.lock"
    timeout /t 1 /nobreak >nul
    schtasks /run /tn "ArchiTracker" >nul 2>&1
    powershell -NoProfile -Command ^
        "Add-Type -AssemblyName System.Windows.Forms; " ^
        "[System.Windows.Forms.MessageBox]::Show('Tracker atualizado para versao %VER_REMOTE% e reiniciado!', 'ArchiTracker', 'OK', 'Information')" >nul 2>&1
) else (
    powershell -NoProfile -Command ^
        "Add-Type -AssemblyName System.Windows.Forms; " ^
        "[System.Windows.Forms.MessageBox]::Show('Erro ao baixar atualizacao. Verifique sua conexao com a internet.', 'ArchiTracker', 'OK', 'Error')" >nul 2>&1
)
goto MENU

:: ================================================
:REINICIAR
schtasks /end /tn "ArchiTracker" >nul 2>&1
schtasks /end /tn "ArchiTrackerWatchdog" >nul 2>&1
taskkill /f /im python.exe >nul 2>&1
taskkill /f /im wscript.exe >nul 2>&1
timeout /t 3 /nobreak >nul
if exist "C:\tracker-arquitetura\tracker.lock" del /f /q "C:\tracker-arquitetura\tracker.lock"
schtasks /run /tn "ArchiTracker" >nul 2>&1
powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.Windows.Forms; " ^
    "[System.Windows.Forms.MessageBox]::Show('Tracker reiniciado!', 'ArchiTracker', 'OK', 'Information')" >nul 2>&1
goto MENU

:: ================================================
:STATUS
tasklist /fi "imagename eq python.exe" 2>nul | find /i "python.exe" >nul 2>&1
if %errorlevel% equ 0 (
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
    "Write-Output $r" > "%TEMP%\archi_confirm.txt"

set /p CONFIRM=<"%TEMP%\archi_confirm.txt"
del "%TEMP%\archi_confirm.txt" >nul 2>&1

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
    if exist "C:\tracker-arquitetura\tracker.lock" del /f /q "C:\tracker-arquitetura\tracker.lock" >nul 2>&1
    timeout /t 2 /nobreak >nul
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -Path 'C:\tracker-arquitetura' -Recurse -Force -ErrorAction SilentlyContinue"
    timeout /t 2 /nobreak >nul
    if exist "C:\tracker-arquitetura" rd /s /q "C:\tracker-arquitetura" >nul 2>&1
    :: Remover atalho da area de trabalho
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
