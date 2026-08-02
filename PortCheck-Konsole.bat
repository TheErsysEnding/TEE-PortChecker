@echo off
REM ===========================================================================
REM  PortCheck - Konsolenfassung starten
REM ===========================================================================
REM  Gleiche Messtechnik wie die Oberflaeche, nur im Textfenster.
REM  Nuetzlich auf Servern ohne Desktop und fuer Fernwartung.
REM ===========================================================================
chcp 65001 >nul
title PortCheck (Konsole)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\PortCheck.Cli.ps1"
echo.
pause
