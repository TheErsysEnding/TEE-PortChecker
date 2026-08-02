#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - Konsolenfassung
================================================================================
 Dieselbe Engine wie die grafische Oberfläche, nur ohne Fenster. Gedacht für
 Server ohne Desktop, für Fernwartung über SSH und für Automatisierung.

 Von TheErsysEnding
   Discord:  https://discord.gg/teebug
   Links:    https://linktr.ee/theersysending

 Beispiele:
   .\PortCheck.Cli.ps1                          Menü
   .\PortCheck.Cli.ps1 -Ports "80,443,3074"     direkt prüfen
   .\PortCheck.Cli.ps1 -Ports "27000-27050" -Csv ergebnis.csv
   .\PortCheck.Cli.ps1 -Preset bo2-ps3          Preset prüfen
   .\PortCheck.Cli.ps1 -NatOnly                 nur NAT-Typ messen
   .\PortCheck.Cli.ps1 -ListPresets             alle Presets auflisten

 Lizenz: MIT (siehe LICENSE)
================================================================================
#>

param(
    [string]$Ports = '',
    [string]$Preset = '',
    [string]$Csv = '',
    [int]$DelayMs = 1200,
    [int]$TimeoutSec = 20,
    [switch]$NoListener,
    [switch]$NatOnly,
    [switch]$ListPresets,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest

$script:AppName     = 'TEE PortChecker'
$script:AppVersion  = '1.1.0'
$script:DiscordUrl  = 'https://discord.gg/teebug'
$script:LinktreeUrl = 'https://linktr.ee/theersysending'

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try { $Host.UI.RawUI.WindowTitle = "$script:AppName $script:AppVersion" } catch { }

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:Root 'PortCheck.Core.ps1')
. (Join-Path $script:Root 'PortCheck.Presets.ps1')

$script:PublicIP = $null
$script:Presets  = @(Get-PortCheckPresets)

# ------------------------------------------------------------------------------
# Region: Ausgabe-Helfer
# ------------------------------------------------------------------------------

function Write-Rule {
    param([string]$Text = '')
    if ($Text) {
        Write-Host ''
        Write-Host "  --- $Text " -NoNewline -ForegroundColor Cyan
        Write-Host ('-' * [Math]::Max(0, 66 - $Text.Length)) -ForegroundColor DarkCyan
    } else {
        Write-Host ('  ' + ('=' * 70)) -ForegroundColor DarkCyan
    }
}

function Read-Line {
    param([string]$Prompt)
    Write-Host $Prompt -NoNewline -ForegroundColor Cyan
    return [Console]::In.ReadLine()
}

function Get-StatusColor {
    param([string]$Status)
    switch ($Status) {
        'Open'   { 'Green' }
        'Closed' { 'Red' }
        default  { 'Yellow' }
    }
}

function Get-StatusText {
    param([string]$Status)
    switch ($Status) {
        'Open'    { 'OFFEN' }
        'Closed'  { 'GESCHLOSSEN' }
        'Unknown' { 'UNBEKANNT' }
        default   { 'FEHLER' }
    }
}

# ------------------------------------------------------------------------------
# Region: Port-Test
# ------------------------------------------------------------------------------

function Invoke-CliPortCheck {
    param(
        [int[]]$PortList,
        [string]$CsvPath = ''
    )

    if (-not $PortList -or $PortList.Count -eq 0) {
        Write-Host '  Keine gültigen Ports angegeben.' -ForegroundColor Red
        return
    }

    if ($PortList.Count -gt 50 -and -not $NonInteractive) {
        $sekunden = [math]::Round($PortList.Count * (($DelayMs / 1000.0) + 1.3))
        $dauer    = [timespan]::FromSeconds($sekunden).ToString('hh\:mm\:ss')
        Write-Host ''
        Write-Host "  ACHTUNG: $($PortList.Count) Ports - geschätzte Dauer ca. $dauer" -ForegroundColor Yellow
        Write-Host '  Der externe Dienst begrenzt die Anfragen; schneller geht es nicht.' -ForegroundColor DarkGray
        $antwort = Read-Line '  Wirklich starten? Tippe JA: '
        if ($antwort.Trim() -ne 'JA') { Write-Host '  Abgebrochen.'; return }
    }

    Write-Host ''
    Write-Host "  Prüfe $($PortList.Count) Port(s) auf $script:PublicIP ..." -ForegroundColor White
    if (-not $NoListener) {
        Write-Host '  Kommt eine Windows-Firewall-Abfrage: ZULASSEN, sonst schlägt der Test fehl.' -ForegroundColor DarkGray
    }
    Write-Host ''

    $ergebnisse = New-Object 'System.Collections.Generic.List[object]'
    $fehlerkette = 0
    $index = 0
    $start = Get-Date

    foreach ($port in $PortList) {
        $index++
        if ($PortList.Count -ge 10) {
            Write-Progress -Activity 'TEE PortChecker' -Status "Port $port ($index von $($PortList.Count))" `
                           -PercentComplete (100 * $index / $PortList.Count)
        }

        if ($NoListener) {
            $r = Test-PortExternal -Port $port -PublicIP $script:PublicIP -TimeoutSec $TimeoutSec -NoListener
        } else {
            $r = Test-PortExternal -Port $port -PublicIP $script:PublicIP -TimeoutSec $TimeoutSec
        }
        $ergebnisse.Add($r)

        $zeile = '  Port {0,-6} -> {1,-12}' -f $r.Port, (Get-StatusText $r.Status)
        if ($r.Note) { $zeile += " ($($r.Note))" }
        Write-Host $zeile -ForegroundColor (Get-StatusColor $r.Status)

        if ($r.Status -eq 'Error' -or $r.Status -eq 'Unknown') { $fehlerkette++ } else { $fehlerkette = 0 }
        if ($fehlerkette -ge 3) {
            Write-Host '  Mehrere Fehler in Folge - vermutlich Rate-Limit. Pause ...' -ForegroundColor Yellow
            Start-Sleep -Seconds 8
            $fehlerkette = 0
        }
        Start-Sleep -Milliseconds $DelayMs
    }
    Write-Progress -Activity 'TEE PortChecker' -Completed

    $alle    = $ergebnisse.ToArray()
    $offen   = @($alle | Where-Object { $_.Status -eq 'Open' })
    $zu      = @($alle | Where-Object { $_.Status -eq 'Closed' })
    $sonstig = $alle.Count - $offen.Count - $zu.Count
    $dauer   = [timespan]::FromSeconds([math]::Round(((Get-Date) - $start).TotalSeconds)).ToString('hh\:mm\:ss')

    Write-Rule 'Ergebnis'
    Write-Host ("   OFFEN:            {0}" -f $offen.Count) -ForegroundColor Green
    Write-Host ("   GESCHLOSSEN:      {0}" -f $zu.Count)    -ForegroundColor Red
    Write-Host ("   FEHLER/UNBEKANNT: {0}" -f $sonstig)     -ForegroundColor Yellow
    Write-Host ("   Dauer:            {0}" -f $dauer)       -ForegroundColor DarkGray

    if ($offen.Count -gt 0) {
        Write-Host "   Offene Ports: $(ConvertTo-PortSpec -Ports @($offen | ForEach-Object { $_.Port }))" -ForegroundColor Green
    }
    if ($offen.Count -eq 0 -and $zu.Count -gt 0) {
        Write-Host ''
        Write-Host '   Alles geschlossen? Die üblichen Ursachen:' -ForegroundColor Yellow
        Write-Host '    - Keine Portweiterleitung im Router, oder auf die falsche lokale IP'
        Write-Host '    - Windows-Firewall blockiert (Abfrage übersehen?)'
        Write-Host '    - Anbieter nutzt CGNAT/DS-Lite -> Weiterleitung unmöglich (Menü [5] prüft das)'
        Write-Host '    - Zwei Router hintereinander (doppeltes NAT)'
    }

    if ($CsvPath) {
        try {
            Export-PortCheckResult -Results $alle -Path $CsvPath -Format 'csv' -PublicIP $script:PublicIP
            Write-Host "`n   Gespeichert: $CsvPath" -ForegroundColor Green
        } catch {
            Write-Host "`n   Speichern fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        }
    } elseif (-not $NonInteractive) {
        $speichern = Read-Line "`n  Ergebnis als CSV speichern? (j/n): "
        if ($speichern.Trim() -match '^[jJ]') {
            $datei = Join-Path $PWD ('portcheck_{0:yyyy-MM-dd_HHmm}.csv' -f (Get-Date))
            Export-PortCheckResult -Results $alle -Path $datei -Format 'csv' -PublicIP $script:PublicIP
            Write-Host "  Gespeichert: $datei" -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------------------------
# Region: Presets
# ------------------------------------------------------------------------------

function Show-CliPresetList {
    param([string]$Filter = '')

    $liste = if ($Filter) {
        @($script:Presets | Where-Object {
            "$($_.Id) $($_.Name) $($_.Vendor) $($_.Platform) $($_.Category)".ToLower() -like "*$($Filter.ToLower())*" })
    } else { $script:Presets }

    $kategorie = ''
    foreach ($p in ($liste | Sort-Object Category, Name)) {
        if ($p.Category -ne $kategorie) {
            $kategorie = $p.Category
            Write-Host ''
            Write-Host "   $kategorie" -ForegroundColor Cyan
        }
        $aufgeloest = Resolve-PresetPorts -Preset $p -AllPresets $script:Presets
        Write-Host ('     {0,-14} {1,-30} TCP {2,-3} UDP {3}' -f
                    $p.Id, $p.Name, $aufgeloest.TCP.Count, $aufgeloest.UDP.Count)
    }
    Write-Host ''
    Write-Host "   $($liste.Count) Einträge. Prüfen mit: -Preset <id>" -ForegroundColor DarkGray
}

function Invoke-CliPreset {
    param([string]$Id)

    $treffer = @($script:Presets | Where-Object { $_.Id -eq $Id })
    if ($treffer.Count -eq 0) {
        Write-Host "  Preset '$Id' gibt es nicht. Liste mit -ListPresets." -ForegroundColor Red
        return
    }

    $preset     = $treffer[0]
    $aufgeloest = Resolve-PresetPorts -Preset $preset -AllPresets $script:Presets

    Write-Rule $preset.Name
    if ($aufgeloest.BaseName) {
        Write-Host "   Enthält die Basisports von: $($aufgeloest.BaseName)" -ForegroundColor DarkGray
    }
    if ($preset.Note) { Write-Host "   $($preset.Note)" -ForegroundColor DarkGray }
    Write-Host "   TCP (wird geprüft): $(ConvertTo-PortSpec -Ports $aufgeloest.TCP)" -ForegroundColor White
    if ($aufgeloest.UDP.Count -gt 0) {
        Write-Host "   UDP (nicht prüfbar, im Router freigeben): $(ConvertTo-PortSpec -Ports $aufgeloest.UDP)" -ForegroundColor DarkYellow
    }

    Invoke-CliPortCheck -PortList $aufgeloest.TCP -CsvPath $Csv
}

# ------------------------------------------------------------------------------
# Region: NAT und Netzwerk
# ------------------------------------------------------------------------------

function Show-CliNat {
    Write-Rule 'NAT-Typ (STUN)'
    Write-Host '   Frage mehrere STUN-Server ab (5-15 Sekunden) ...' -ForegroundColor DarkGray

    $mappings = Get-StunMappings -TimeoutMs 2500
    $lokal    = Get-LocalPrimaryIP
    $bewertung = Get-NatAssessment -Mappings $mappings -LocalIP $lokal -PublicIP $script:PublicIP

    Write-Host ''
    foreach ($m in $bewertung.Mappings) {
        Write-Host ('   {0,-28} sieht dich als {1}:{2}' -f $m.Server, $m.ExtIP, $m.ExtPort) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host "   Lokale IP:      $lokal"
    Write-Host "   Öffentliche IP: $script:PublicIP"
    Write-Host ''

    $farbe = switch ($bewertung.Level) {
        'Open'     { 'Green' }
        'Moderate' { 'Yellow' }
        default    { 'Red' }
    }
    Write-Host "   ERGEBNIS: $($bewertung.Title)  ($($bewertung.Behaviour))" -ForegroundColor $farbe
    Write-Host ''
    foreach ($grund in $bewertung.Reasons) {
        Write-Host "    - $grund" -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '   Ehrlich dazugesagt: messbar ist das Mapping-Verhalten (RFC 5780).' -ForegroundColor DarkGray
    Write-Host '   Das Filter-Verhalten braucht einen Server mit zweiter IP - das kann' -ForegroundColor DarkGray
    Write-Host '   dieser Test nicht leisten. Deshalb steht bei gutmütigem NAT MODERAT.' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-CliNetwork {
    Write-Rule 'Netzwerk'
    $netz = Get-NetworkOverview

    Write-Host "   Rechnername:     $($netz.HostName)"
    Write-Host "   Gateway:         $(if ($netz.Gateway) { $netz.Gateway } else { 'unbekannt' })"
    Write-Host "   Lokale IPs:      $($netz.LocalIPs -join ', ')"
    Write-Host "   DNS-Server:      $($netz.DnsServers -join ', ')"
    Write-Host "   Öffentliche IP:  $script:PublicIP"

    Write-Host ''
    Write-Host '   Netzwerkadapter:' -ForegroundColor Cyan
    foreach ($a in $netz.Adapters) {
        $tempo = if ($a.SpeedMbps -gt 0) { "$($a.SpeedMbps) Mbit/s" } else { $a.Type }
        Write-Host ('     {0,-22} {1,-16} {2}' -f $a.Name, $a.IPv4, $tempo)
    }

    Write-Host ''
    Write-Host '   Suche UPnP-Geräte (ca. 3 Sekunden) ...' -ForegroundColor DarkGray
    $geraete = Get-UpnpDevices -TimeoutMs 3500
    if (@($geraete).Count -gt 0) {
        Write-Host "   UPnP verfügbar - $(@($geraete).Count) Gerät(e):" -ForegroundColor Green
        foreach ($g in $geraete) {
            Write-Host "     $($g.Address)  $($g.Server)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host '   UPnP: keine Antwort. Im Router deaktiviert, oder er antwortet nicht auf SSDP.' -ForegroundColor Yellow
    }
    Write-Host ''
}

# ------------------------------------------------------------------------------
# Region: Menü
# ------------------------------------------------------------------------------

function Show-Menu {
    Clear-Host
    Write-Rule
    Write-Host '   TEE' -NoNewline -ForegroundColor Cyan
    Write-Host " PortChecker $script:AppVersion" -NoNewline -ForegroundColor White
    Write-Host '  -  Erreichbarkeit aus dem Internet prüfen' -ForegroundColor Gray
    Write-Rule
    Write-Host ''
    Write-Host "   Deine öffentliche IP: $script:PublicIP" -ForegroundColor White
    Write-Host ''
    Write-Host '   NAT-Typen beim Gaming zur Einordnung:' -ForegroundColor DarkGray
    Write-Host '    OFFEN    = benötigte Ports aus dem Internet erreichbar' -ForegroundColor DarkGray
    Write-Host '    MODERAT  = nur teilweise erreichbar / UPnP hilft nach' -ForegroundColor DarkGray
    Write-Host '    STRIKT   = nichts erreichbar (CGNAT, doppeltes NAT, Firewall)' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [1] Eigene Ports prüfen   (1-3000 | 80,443,3074 | gemischt)'
    Write-Host '   [2] Spiele-Presets        (Konsolen, Call of Duty, Shooter, Server ...)'
    Write-Host '   [3] Alle Ports 1-65535    (dauert sehr lange!)'
    Write-Host '   [4] Netzwerk & UPnP'
    Write-Host '   [5] NAT-Typ messen        -> OFFEN / MODERAT / STRIKT'
    Write-Host '   [6] Grafische Oberfläche starten'
    Write-Host '   [0] Beenden'
    Write-Host ''
    Write-Host '   ------------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '   Kostenlos und quelloffen. Danke, dass du mein Tool benutzt!' -ForegroundColor DarkGray
    Write-Host '   Discord: ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'discord.gg/teebug' -NoNewline -ForegroundColor Cyan
    Write-Host '   Links: ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'linktr.ee/theersysending' -ForegroundColor Cyan
    Write-Host ''
}

# ------------------------------------------------------------------------------
# Region: Start
# ------------------------------------------------------------------------------

function Show-CliFooter {
    Write-Host ''
    Write-Host '  ------------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host "  $script:AppName $script:AppVersion - kostenlos und quelloffen." -ForegroundColor DarkGray
    Write-Host '  Discord ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'discord.gg/teebug' -NoNewline -ForegroundColor Cyan
    Write-Host '  |  Links ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'linktr.ee/theersysending' -ForegroundColor Cyan
    Write-Host ''
}

if ($ListPresets) {
    Show-CliPresetList
    Show-CliFooter
    exit 0
}

Write-Host '  Ermittle öffentliche IP ...' -ForegroundColor DarkGray
$script:PublicIP = Get-PublicIPAddress
if (-not $script:PublicIP) {
    Write-Host '  FEHLER: Öffentliche IP nicht ermittelbar. Besteht eine Internetverbindung?' -ForegroundColor Red
    exit 1
}

if ($NatOnly)  { Show-CliNat; Show-CliFooter; exit 0 }
if ($Preset)   { Invoke-CliPreset -Id $Preset; Show-CliFooter; exit 0 }
if ($Ports.Trim() -ne '') {
    $zerlegt = ConvertFrom-PortSpec -Spec $Ports
    if ($zerlegt.Invalid.Count -gt 0) {
        Write-Host "  Übersprungen (nicht verstanden): $($zerlegt.Invalid -join ', ')" -ForegroundColor Yellow
    }
    Write-Host "  Öffentliche IP: $script:PublicIP"
    Invoke-CliPortCheck -PortList $zerlegt.Ports -CsvPath $Csv
    Show-CliFooter
    exit 0
}

if ($NonInteractive) {
    Write-Host '  Nichts zu tun. Nutze -Ports, -Preset, -NatOnly oder -ListPresets.' -ForegroundColor Yellow
    exit 0
}

while ($true) {
    Show-Menu
    $wahl = (Read-Line '   Auswahl: ').Trim()
    switch ($wahl) {
        '1' {
            $eingabe = Read-Line "`n   Ports (z. B. 1-3000 oder 80,443,3074): "
            $zerlegt = ConvertFrom-PortSpec -Spec $eingabe
            if ($zerlegt.Invalid.Count -gt 0) {
                Write-Host "   Übersprungen: $($zerlegt.Invalid -join ', ')" -ForegroundColor Yellow
            }
            Invoke-CliPortCheck -PortList $zerlegt.Ports
            [void](Read-Line "`n   Enter für Menü ...")
        }
        '2' {
            $suche = Read-Line "`n   Suchbegriff (leer = alle anzeigen): "
            Show-CliPresetList -Filter $suche.Trim()
            $id = Read-Line "`n   Preset-Id eingeben (leer = zurück): "
            if ($id.Trim()) { Invoke-CliPreset -Id $id.Trim() }
            [void](Read-Line "`n   Enter für Menü ...")
        }
        '3' {
            Invoke-CliPortCheck -PortList (1..65535)
            [void](Read-Line "`n   Enter für Menü ...")
        }
        '4' { Show-CliNetwork; [void](Read-Line '   Enter für Menü ...') }
        '5' { Show-CliNat;     [void](Read-Line '   Enter für Menü ...') }
        '6' {
            $gui = Join-Path $script:Root 'PortCheck.Gui.ps1'
            Start-Process powershell.exe -ArgumentList @(
                '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$gui`"")
            Write-Host '   Oberfläche wird gestartet ...' -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
        '0' { exit 0 }
        default { }
    }
}
