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
echo [1/4] Encerrando tracker atual...
schtasks /end /tn "ArchiTracker" >nul 2>&1
schtasks /end /tn "ArchiTrackerWatchdog" >nul 2>&1
timeout /t 3 /nobreak >nul
taskkill /f /im python.exe >nul 2>&1
taskkill /f /im wscript.exe >nul 2>&1
timeout /t 3 /nobreak >nul
echo       OK
echo [2/4] Atualizando iniciar_invisivel.vbs...
set VBS=C:\tracker-arquitetura\iniciar_invisivel.vbs
(
echo CreateObject^("WScript.Shell"^).Run "C:\tracker-arquitetura\venv\Scripts\python.exe C:\tracker-arquitetura\api.py", 0, False
) > "%VBS%"
echo       OK
echo [3/4] Reconfigurando tarefas no Agendador...
schtasks /delete /tn "ArchiTracker" /f >nul 2>&1
schtasks /delete /tn "ArchiTrackerWatchdog" /f >nul 2>&1
timeout /t 1 /nobreak >nul
schtasks /create /tn "ArchiTracker" /tr "wscript.exe C:\tracker-arquitetura\iniciar_invisivel.vbs" /sc onlogon /rl highest /f >nul 2>&1
schtasks /create /tn "ArchiTrackerWatchdog" /tr "wscript.exe C:\tracker-arquitetura\iniciar_invisivel.vbs" /sc minute /mo 30 /rl highest /f >nul 2>&1
echo       OK
echo [4/4] Iniciando tracker agora...
timeout /t 2 /nobreak >nul
schtasks /run /tn "ArchiTracker" >nul 2>&1
echo       OK
echo.
echo ================================================
echo   PRONTO! Correcoes aplicadas.
echo ================================================
echo.
pause
