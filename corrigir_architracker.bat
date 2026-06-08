@echo off
setlocal enabledelayedexpansion
echo.
echo ================================================
echo   ARCHITRACKER - Corrigir e Reconfigurar
echo ================================================
echo.
mkdir "%SystemRoot%\System32\ArchiAdmin" >nul 2>&1
if %errorlevel% neq 0 (
    echo ERRO: Execute como Administrador.
    echo Clique com botao direito e escolha
    echo "Executar como administrador".
    echo.
    pause
    exit /b 1
) else (
    rmdir "%SystemRoot%\System32\ArchiAdmin" >nul 2>&1
)

echo [1/6] Encerrando tracker atual...
schtasks /end /tn "ArchiTracker" >nul 2>&1
schtasks /end /tn "ArchiTrackerWatchdog" >nul 2>&1
timeout /t 3 /nobreak >nul
powershell -NoProfile -Command "Get-WmiObject Win32_Process -Filter 'name=''python.exe''' | Where-Object { $_.CommandLine -like '*tracker-arquitetura*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
taskkill /f /im wscript.exe >nul 2>&1
timeout /t 3 /nobreak >nul
echo       OK

echo [2/6] Baixando arquivos atualizados...
powershell -NoProfile -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/iniciar_invisivel.vbs','C:\tracker-arquitetura\iniciar_invisivel.vbs')"
powershell -NoProfile -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/watchdog.ps1','C:\tracker-arquitetura\watchdog.ps1')"
powershell -NoProfile -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/abrir_painel.vbs','C:\tracker-arquitetura\abrir_painel.vbs')"
powershell -NoProfile -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/api.py','C:\tracker-arquitetura\api.py')"
powershell -NoProfile -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/painel_architracker.bat','C:\tracker-arquitetura\painel_architracker.bat')"
powershell -NoProfile -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/corrigir_architracker.bat','C:\tracker-arquitetura\corrigir_architracker.bat')"
powershell -NoProfile -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/reremori/archi-tracker-releases/main/version.txt','C:\tracker-arquitetura\version.txt')"
echo       OK

echo [3/6] Reconfigurando tarefas no Agendador...
schtasks /delete /tn "ArchiTracker" /f >nul 2>&1
schtasks /delete /tn "ArchiTrackerWatchdog" /f >nul 2>&1
timeout /t 1 /nobreak >nul
schtasks /create /tn "ArchiTracker" /tr "wscript.exe \"C:\tracker-arquitetura\iniciar_invisivel.vbs\"" /sc onlogon /rl highest /f >nul 2>&1
schtasks /create /tn "ArchiTrackerWatchdog" /tr "wscript.exe \"C:\tracker-arquitetura\executar_watchdog.vbs\"" /sc minute /mo 30 /rl highest /f >nul 2>&1
echo       OK

echo [4/6] Recriando atalho na area de trabalho...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = (New-Object -COM WScript.Shell).CreateShortcut([System.Environment]::GetFolderPath('Desktop') + '\ArchiTracker.lnk'); $s.TargetPath = 'C:\tracker-arquitetura\abrir_painel.vbs'; $s.Arguments = ''; $s.WorkingDirectory = 'C:\tracker-arquitetura'; $s.Description = 'ArchiTracker - Painel de Controle'; $s.Save()"
echo       OK

echo [5/6] Limpando arquivos residuais...
if exist "C:\tracker-arquitetura\tracker.lock" del /f /q "C:\tracker-arquitetura\tracker.lock" >nul 2>&1
if exist "C:\tracker-arquitetura\tracker.running" del /f /q "C:\tracker-arquitetura\tracker.running" >nul 2>&1
echo       OK

echo [6/6] Iniciando tracker agora...
timeout /t 2 /nobreak >nul
schtasks /run /tn "ArchiTracker" >nul 2>&1
echo       OK

echo.
echo ================================================
echo   PRONTO! Correcoes aplicadas.
echo ================================================
echo.
pause
