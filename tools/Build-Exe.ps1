#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - Starter uebersetzen
================================================================================
 Baut TEE-PortChecker.exe aus tools\Launcher.cs.

 Uebersetzt wird mit dem C#-Compiler des .NET Framework 4, der auf jedem
 Windows 10 und 11 ohnehin vorhanden ist. Kein Visual Studio, kein SDK, kein
 Download - deshalb kann jeder das Ergebnis selbst nachbauen und mit der
 mitgelieferten Datei vergleichen.

 Aufruf:  .\tools\Build-Exe.ps1
================================================================================
#>

param(
    [switch]$KeepIntermediate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$wurzel  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$quelle  = Join-Path $wurzel 'tools\Launcher.cs'
$symbol  = Join-Path $wurzel 'docs\TEE-PortChecker.ico'
$ziel    = Join-Path $wurzel 'TEE-PortChecker.exe'

if (-not (Test-Path $quelle)) { throw "Quelldatei fehlt: $quelle" }

# Symbol notfalls erzeugen, damit ein frischer Klon direkt bauen kann.
if (-not (Test-Path $symbol)) {
    Write-Host '  Symbol fehlt - wird erzeugt ...' -ForegroundColor Yellow
    & (Join-Path $wurzel 'tools\New-AppIcon.ps1') | Out-Null
}

$compiler = Get-ChildItem 'C:\Windows\Microsoft.NET\Framework64' -Filter 'csc.exe' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -like '*v4.0*' } |
            Select-Object -First 1
if (-not $compiler) {
    $compiler = Get-ChildItem 'C:\Windows\Microsoft.NET\Framework' -Filter 'csc.exe' -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.DirectoryName -like '*v4.0*' } |
                Select-Object -First 1
}
if (-not $compiler) {
    throw 'Kein C#-Compiler gefunden. Erwartet unter C:\Windows\Microsoft.NET\Framework64\v4.0.*\csc.exe'
}

Write-Host "  Compiler : $($compiler.FullName)"
Write-Host "  Quelle   : $quelle"
Write-Host "  Symbol   : $symbol"
Write-Host ''

$argumente = @(
    '/nologo'
    '/target:winexe'          # Fensteranwendung - kein Konsolenfenster
    '/optimize+'
    '/platform:anycpu'
    "/win32icon:$symbol"
    '/reference:System.dll'
    '/reference:System.Windows.Forms.dll'
    "/out:$ziel"
    $quelle
)

& $compiler.FullName @argumente
if ($LASTEXITCODE -ne 0) { throw "Uebersetzen fehlgeschlagen (Rueckgabewert $LASTEXITCODE)." }

if (-not $KeepIntermediate) {
    Remove-Item (Join-Path $wurzel 'TEE-PortChecker.pdb') -ErrorAction SilentlyContinue
}

$datei = Get-Item $ziel
Write-Host ''
Write-Host "  Fertig: $($datei.FullName)" -ForegroundColor Green
Write-Host ("  Groesse: {0:N0} Byte" -f $datei.Length)
Write-Host ''
Write-Host '  Hinweis: Die Datei ist NICHT signiert. Beim ersten Start aus dem Internet' -ForegroundColor Yellow
Write-Host '  zeigt Windows deshalb eine SmartScreen-Warnung. Eine Signatur kostet Geld' -ForegroundColor Yellow
Write-Host '  und ist an eine Firma oder eine ausgewiesene Person gebunden.' -ForegroundColor Yellow
