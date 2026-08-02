@echo off
REM ===========================================================================
REM  PortCheck - grafische Oberflaeche starten
REM ===========================================================================
REM  Doppelklick genuegt. Es wird nichts installiert und nichts in die
REM  Registry geschrieben. Der Quelltext liegt vollstaendig im Ordner "src".
REM
REM  -STA ist Pflicht: WPF und die Zwischenablage brauchen dieses Threading-
REM  Modell. -ExecutionPolicy Bypass gilt nur fuer diesen einen Start und
REM  aendert nichts an den Einstellungen des Rechners.
REM ===========================================================================
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\PortCheck.Gui.ps1"
