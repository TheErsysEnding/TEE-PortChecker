#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - Grafische Oberfläche
================================================================================
 Einstiegspunkt der Anwendung.

 AUFBAU:
   Gui.xaml              Aussehen und Anordnung
   PortCheck.Core.ps1    Messlogik, völlig ohne Oberfläche
   PortCheck.Presets.ps1 Portlisten der Spiele
   PortCheck.Themes.ps1  Farbwelten

 WARUM HINTERGRUND-RUNSPACES:
   Ein Port-Test dauert pro Port über eine Sekunde. Liefe das im
   Oberflächen-Thread, wäre das Fenster die ganze Zeit eingefroren -
   der klassische "Reagiert nicht"-Zustand. Stattdessen läuft die Messung
   in einem eigenen Runspace und meldet Zwischenstände über eine
   threadsichere Warteschlange. Ein Timer im Oberflächen-Thread leert diese
   Warteschlange und zeichnet neu. So bleibt das Fenster jederzeit bedienbar
   und der Abbrechen-Knopf reagiert sofort.

 Lizenz: MIT (siehe LICENSE)
 Projekt: https://github.com/TheErsysEnding/TEE-PortChecker
================================================================================
#>

param(
    # Startet mit vorgewählter Farbwelt, z. B. -Theme crimson
    [string]$Theme = '',

    # Startet direkt auf einer bestimmten Seite, z. B. -StartPage NavNat
    [ValidateSet('', 'NavDashboard', 'NavPorts', 'NavPresets', 'NavNat', 'NavHowTo', 'NavSecurity', 'NavQuality', 'NavNetwork', 'NavSettings', 'NavAbout')]
    [string]$StartPage = '',

    # ENTWICKLER-OPTION: baut das Fenster vollständig auf, prüft alles durch
    # und beendet sich wieder, ohne etwas anzuzeigen. Wird von der Testsuite
    # und der GitHub-Action benutzt.
    [switch]$SelfTest,

    # ENTWICKLER-OPTION: legt nach dem Start ein Abbild des Fensters als PNG ab
    # und beendet sich. Damit werden die Bilder für die README erzeugt.
    [string]$CaptureTo = '',

    # Wartezeit vor dem Abbild. Mit echten Daten länger, weil erst das Netz
    # befragt werden muss.
    [int]$CaptureDelayMs = 1400,

    # ENTWICKLER-OPTION: führt nach dem Start eine ECHTE Messung der
    # angegebenen Ports durch, meldet das Ergebnis als Text und beendet sich.
    # Damit lässt sich der komplette Weg Runspace -> Warteschlange -> Anzeige
    # automatisch prüfen, nicht nur mit Beispieldaten.
    [string]$LiveTest = '',

    # Zeigt das Willkommensfenster erneut, auch wenn es schon zu sehen war.
    [switch]$ShowWelcome,

    # ENTWICKLER-OPTION: öffnet direkt das Teilen-Fenster (für die Bilder).
    [switch]$ShowShare,

    # ENTWICKLER-OPTION: füllt die Oberfläche mit Beispieldaten und geht
    # NICHT ins Netz. Dient allein den Bildern in der README - damit dort
    # keine echte IP-Adresse einer Privatperson landet. Die verwendete Adresse
    # stammt aus dem Dokumentationsbereich 203.0.113.0/24 (RFC 5737), der
    # weltweit niemandem gehört.
    [switch]$DemoMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------
# Region: Laden
# ------------------------------------------------------------------------------

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$script:AppName    = 'TEE PortChecker'
$script:AppVersion = '1.1.0'
$script:RepoUrl    = 'https://github.com/TheErsysEnding/TEE-PortChecker'
$script:LinktreeUrl = 'https://linktr.ee/theersysending'
$script:DiscordUrl  = 'https://discord.gg/teebug'

# Empfehlungslink (Werbung). In der Oberfläche wird nur "PureVPN.com" angezeigt,
# damit die lange Kennung niemanden erschlägt - geöffnet wird die vollständige
# Adresse. Die Kennzeichnung als Werbung steht sichtbar daneben; das ist in
# Deutschland Pflicht und schützt den Betreiber.
$script:PureVpnUrl = 'https://www.purevpn.com/refer-a-friend-v2?referrer=MDErTXhqMGlVdjlaMGFhd01KSW5wanZQcG9FbzFoMGRWaWhOZDEra01ldHNzYlFZaUxUei9NbCtjZDNkcDBHRw=='
$script:Root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CorePath   = Join-Path $script:Root 'PortCheck.Core.ps1'
$script:PresetPath = Join-Path $script:Root 'PortCheck.Presets.ps1'
$script:ThemePath  = Join-Path $script:Root 'PortCheck.Themes.ps1'
$script:UpnpPath   = Join-Path $script:Root 'PortCheck.Upnp.ps1'
$script:DiagPath   = Join-Path $script:Root 'PortCheck.Diagnose.ps1'
$script:XamlPath   = Join-Path $script:Root 'Gui.xaml'
$script:WelcomePath = Join-Path $script:Root 'Welcome.xaml'
$script:SharePath  = Join-Path $script:Root 'Share.xaml'

foreach ($required in @($script:CorePath, $script:PresetPath, $script:ThemePath,
                        $script:UpnpPath, $script:DiagPath,
                        $script:XamlPath, $script:WelcomePath, $script:SharePath)) {
    if (-not (Test-Path $required)) {
        [System.Windows.MessageBox]::Show(
            "Eine Programmdatei fehlt:`n$required`n`nBitte den kompletten Ordner entpacken bzw. klonen.",
            'TEE PortChecker', 'OK', 'Error') | Out-Null
        exit 1
    }
}

. $script:CorePath
. $script:PresetPath
. $script:ThemePath
. $script:UpnpPath
. $script:DiagPath

# ------------------------------------------------------------------------------
# Region: Einstellungen
# ------------------------------------------------------------------------------

$script:SettingsDir  = Join-Path $env:APPDATA 'TEE-PortChecker'
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'

# Bei Entwickler-Optionen wird nichts dauerhaft gespeichert.
$script:NoPersist = [bool]($SelfTest -or $DemoMode -or $CaptureTo -or $LiveTest)

function Get-DefaultSettings {
    [pscustomobject]@{
        Theme        = 'crimson'
        DelayMs      = 1200
        TimeoutSec   = 20
        UseListener  = $true
        WarnLarge    = $true
        LastPorts    = ''
        # Merkt sich, ob das Willkommensfenster schon zu sehen war. Es soll
        # genau einmal erscheinen und danach nie wieder ungefragt.
        WelcomeShown = $false
    }
}

function Open-ExternalLink {
    <#
    .SYNOPSIS
        Öffnet eine Adresse im Standardbrowser.
    .DESCRIPTION
        Nur für die im Programm fest hinterlegten Adressen gedacht. Es wird
        nichts nachgeladen und nichts übermittelt - der Browser bekommt
        lediglich die Adresse.
    #>
    param([Parameter(Mandatory = $true)][string]$Url)
    try {
        Start-Process $Url
        return $true
    } catch {
        return $false
    }
}

function Import-AppSettings {
    <#
    .SYNOPSIS
        Lädt die Einstellungen; fällt bei jedem Problem auf die Standardwerte
        zurück, damit eine kaputte Datei den Start nie verhindert.
    #>
    $defaults = Get-DefaultSettings
    if (-not (Test-Path $script:SettingsFile)) { return $defaults }
    try {
        $loaded = Get-Content $script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $defaults.PSObject.Properties) {
            if ($loaded.PSObject.Properties.Name -contains $property.Name) {
                $value = $loaded.$($property.Name)
                if ($null -ne $value) { $defaults.$($property.Name) = $value }
            }
        }
    } catch { }
    # Werte begrenzen - schützt vor von Hand verstellten Unsinnswerten
    if ($defaults.DelayMs    -lt 300 -or $defaults.DelayMs    -gt 4000) { $defaults.DelayMs    = 1200 }
    if ($defaults.TimeoutSec -lt 5   -or $defaults.TimeoutSec -gt 60)   { $defaults.TimeoutSec = 20 }
    return $defaults
}

function Export-AppSettings {
    # Entwicklerläufe (Selbsttest, Bilder, Beispieldaten) dürfen die
    # gespeicherten Einstellungen des Anwenders NICHT überschreiben.
    if ($script:NoPersist) { return }
    try {
        if (-not (Test-Path $script:SettingsDir)) {
            New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        }
        $script:Settings | ConvertTo-Json | Set-Content -Path $script:SettingsFile -Encoding UTF8
    } catch { }
}

$script:Settings = Import-AppSettings
if ($Theme) { $script:Settings.Theme = $Theme }

# ------------------------------------------------------------------------------
# Region: Fenster aufbauen
# ------------------------------------------------------------------------------

$xamlDoc = New-Object System.Xml.XmlDocument
$xamlDoc.Load($script:XamlPath)
$script:Win = [System.Windows.Markup.XamlReader]::Load(
    (New-Object System.Xml.XmlNodeReader -ArgumentList $xamlDoc))

function Get-Ui {
    <#
    .SYNOPSIS
        Holt ein benanntes Element aus dem Fenster - mit klarer Fehlermeldung,
        falls der Name im XAML fehlt oder vertippt ist.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)
    $element = $script:Win.FindName($Name)
    if ($null -eq $element) { throw "Element '$Name' fehlt im XAML." }
    return $element
}

# Alle benötigten Elemente einmalig einsammeln.
$ui = @{}
foreach ($name in @(
    'TitleBar','BtnMinimize','BtnMaximize','BtnClose','TxtVersionChip',
    'NavDashboard','NavPorts','NavPresets','NavNat','NavNetwork','NavSettings','NavAbout',
    'TxtSideIp','TxtSideNat','DotNat',
    'PageDashboard','PagePorts','PagePresets','PageNat','PageNetwork','PageSettings','PageAbout',
    'TxtPublicIp','TxtPublicIpNote','TxtLocalIp','TxtGateway','TxtDashNat','TxtDashNatNote',
    'TxtDashUpnp','TxtDashUpnpNote','BtnQuickNat','BtnQuickPresets','BtnQuickRefresh',
    'TxtPortSpec','BtnStart','BtnStop','PanelChips','ProgPorts','TxtPortProgress',
    'TxtCountOpen','TxtCountClosed','TxtCountOther','CmbFilter','BtnCopyOpen','BtnExport',
    'BtnClearResults','LstResults','TxtNoResults',
    'CmbCategory','TxtPresetSearch','ItemsPresets','TxtPresetSelection','TxtPresetUdp',
    'BtnPresetClear','BtnPresetTest','TxtPresetIntro',
    'NatBadge','NatBadgeIcon','NatBadgeText','TxtNatTitle','TxtNatBehaviour','ItemsNatReasons',
    'BtnNatStart','BtnNatCopy','LstNatServers','TxtNatEmpty',
    'BtnUpnpScan','BtnNetRefresh','TxtNetHost','TxtNetGateway','TxtNetDns','TxtNetPublic',
    'ItemsAdapters','TxtUpnpState','ItemsUpnp','VpnWarnCard','TxtVpnWarn',
    'ItemsThemes','SldDelay','TxtDelayValue','SldTimeout','TxtTimeoutValue','ChkListener',
    'ChkWarnLarge','TxtSettingsPath','BtnOpenSettingsFolder','BtnResetSettings',
    'TxtAboutVersion','BtnOpenRepo','BtnOpenSource','BtnShowWelcome',
    'BtnAboutLinktree','BtnAboutDiscord','BtnAboutRepo','TxtRepoShort',
    'BtnSideDiscord','BtnSideLinktree','BtnLinktree','BtnDiscord',
'NavHowTo','PageHowTo','BtnPureVpn','BtnOpenRouter','BtnHowToTest',
    'NavSecurity','PageSecurity','SecurityBadge','SecurityBadgeIcon','SecurityBadgeText',
    'TxtSecurityTitle','TxtSecuritySummary','BtnSecurityScan','BtnSecurityStop',
    'ProgSecurity','TxtSecurityProgress','ItemsSecurityFindings',
    'NavQuality','PageQuality','BtnQualityStart','BtnQualityCopy','TxtQualityProgress','ItemsQuality',
    'Ipv6Icon','BtnIpv6Check','TxtIpv6Title','TxtIpv6Address','ItemsIpv6Reasons',
    'UpnpManageCard','BtnUpnpRefresh','TxtUpnpRouterInfo','ItemsUpnpMappings','TxtUpnpMappingsEmpty',
    'TxtUpnpPort','CmbUpnpProtocol','TxtUpnpDescription','BtnUpnpAdd','BtnShareResult',
    'StatusDot','TxtStatus','ProgStatus','TxtStatusRight')) {
    $ui[$name] = Get-Ui $name
}

# ------------------------------------------------------------------------------
# Region: Theme anwenden
# ------------------------------------------------------------------------------

$script:Themes = @(Get-PortCheckThemes)

function Get-ThemeById {
    param([string]$Id)
    $found = @($script:Themes | Where-Object { $_.Id -eq $Id })
    if ($found.Count -gt 0) { return $found[0] }
    return $script:Themes[0]
}

$script:CurrentTheme  = Get-ThemeById $script:Settings.Theme
$script:StatusBrushes = $null

function Set-WindowDarkMode {
    <#
    .SYNOPSIS
        Meldet Windows die Helligkeit des Fensters und bittet um runde Ecken.
    .DESCRIPTION
        Betrifft den vom System gezeichneten Rahmen und den Schatten. Auf
        älteren Windows-Versionen schlägt der Aufruf einfach fehl - das ist
        eingeplant und stört nicht.
    #>
    param([bool]$Dark)

    if (-not ('PortCheck.Dwm' -as [type])) {
        Add-Type -Namespace 'PortCheck' -Name 'Dwm' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);
'@
    }
    try {
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper($script:Win)).Handle
        if ($handle -eq [IntPtr]::Zero) { return }
        $useDark = [int]$Dark
        # 20 = DWMWA_USE_IMMERSIVE_DARK_MODE, 19 = derselbe Wert vor Build 18985
        [void][PortCheck.Dwm]::DwmSetWindowAttribute($handle, 20, [ref]$useDark, 4)
        [void][PortCheck.Dwm]::DwmSetWindowAttribute($handle, 19, [ref]$useDark, 4)
        # 33 = DWMWA_WINDOW_CORNER_PREFERENCE, 2 = DWMWCP_ROUND
        $round = 2
        [void][PortCheck.Dwm]::DwmSetWindowAttribute($handle, 33, [ref]$round, 4)
    } catch { }
}

function Switch-AppTheme {
    <#
    .SYNOPSIS
        Schaltet auf ein Theme um und färbt bereits angezeigte Daten nach.
    #>
    param([Parameter(Mandatory = $true)]$NewTheme)

    $script:CurrentTheme = $NewTheme
    Set-PortCheckTheme -Window $script:Win -Theme $NewTheme
    $script:StatusBrushes = Get-StatusBrushSet -Theme $NewTheme
    Set-WindowDarkMode -Dark $NewTheme.IsDark

    $script:Settings.Theme = $NewTheme.Id
    Export-AppSettings

    # Bereits vorhandene Ergebnisse tragen ihre Farben als Objekt mit sich -
    # die müssen nach dem Wechsel neu erzeugt werden.
    if ($script:RawResults.Count -gt 0) { Update-ResultView }
    if ($script:LastNat) { Show-NatResult $script:LastNat }
}

# ------------------------------------------------------------------------------
# Region: Statusleiste
# ------------------------------------------------------------------------------

function Set-Status {
    <#
    .SYNOPSIS
        Text und Farbpunkt in der Statusleiste setzen.
    #>
    param(
        [string]$Text,
        [ValidateSet('idle', 'busy', 'ok', 'warn', 'error')][string]$Level = 'idle'
    )
    $ui.TxtStatus.Text = $Text
    $key = switch ($Level) {
        'ok'    { 'OkBrush' }
        'warn'  { 'WarnBrush' }
        'error' { 'BadBrush' }
        'busy'  { 'AccentBrush' }
        default { 'FgFaintBrush' }
    }
    $ui.StatusDot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $key)
}

# ------------------------------------------------------------------------------
# Region: Hintergrundarbeit
# ------------------------------------------------------------------------------

$script:Sync = [hashtable]::Synchronized(@{
    Queue  = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]')
    Cancel = $false
})
$script:Job  = $null
$script:Busy = $false

function Start-Work {
    <#
    .SYNOPSIS
        Startet eine Messung in einem eigenen Runspace.
    .DESCRIPTION
        Der Runspace bekommt nur drei Dinge mit: die gemeinsame Warteschlange,
        die Pfade der Bibliotheken und einen Parametersatz. Er greift NICHT auf
        Oberflächenelemente zu - jede Anzeige läuft über die Warteschlange.
        Das ist die einzige threadsichere Bauweise für WPF.
    #>
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Body,
        [hashtable]$Parameters = @{}
    )

    if ($script:Busy) {
        Set-Status 'Es läuft bereits eine Messung.' 'warn'
        return $false
    }

    $script:Busy = $true
    $script:Sync.Cancel = $false

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = 'ReuseThread'
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('Sync', $script:Sync)
    $runspace.SessionStateProxy.SetVariable('CorePath', $script:CorePath)
    $runspace.SessionStateProxy.SetVariable('PresetPath', $script:PresetPath)
    $runspace.SessionStateProxy.SetVariable('UpnpPath', $script:UpnpPath)
    $runspace.SessionStateProxy.SetVariable('DiagPath', $script:DiagPath)
    $runspace.SessionStateProxy.SetVariable('P', $Parameters)

    $shell = [powershell]::Create()
    $shell.Runspace = $runspace
    [void]$shell.AddScript($Body)

    $script:Job = @{
        Shell    = $shell
        Handle   = $shell.BeginInvoke()
        Runspace = $runspace
    }
    $ui.ProgStatus.Visibility = 'Visible'
    return $true
}

function Stop-Work {
    <#
    .SYNOPSIS
        Bittet die laufende Messung um Abbruch (kein harter Thread-Abbruch).
    #>
    $script:Sync.Cancel = $true
    Set-Status 'Abbruch angefordert - laufende Anfrage wird noch beendet...' 'warn'
}

function Complete-Work {
    <#
    .SYNOPSIS
        Räumt einen beendeten Runspace auf und meldet Fehler des Arbeiters.
    #>
    if (-not $script:Job) { return }
    try {
        [void]$script:Job.Shell.EndInvoke($script:Job.Handle)
        if ($script:Job.Shell.Streams.Error.Count -gt 0) {
            $first = $script:Job.Shell.Streams.Error[0]
            Set-Status "Fehler im Hintergrund: $($first.Exception.Message)" 'error'
        }
    } catch {
        Set-Status "Fehler im Hintergrund: $($_.Exception.Message)" 'error'
    } finally {
        try { $script:Job.Shell.Dispose() } catch { }
        try { $script:Job.Runspace.Close(); $script:Job.Runspace.Dispose() } catch { }
        $script:Job  = $null
        $script:Busy = $false
        $ui.ProgStatus.Visibility = 'Collapsed'
    }
}

# ------------------------------------------------------------------------------
# Region: Ergebnisse
# ------------------------------------------------------------------------------

$script:RawResults = New-Object 'System.Collections.Generic.List[object]'
$script:ViewRows   = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$ui.LstResults.ItemsSource = $script:ViewRows

$script:StatusLabels = @{
    Open    = 'OFFEN'
    Closed  = 'GESCHLOSSEN'
    Unknown = 'UNBEKANNT'
    Error   = 'FEHLER'
}

function New-ResultRow {
    <#
    .SYNOPSIS
        Macht aus einem Messergebnis eine anzeigefertige Zeile.
    .DESCRIPTION
        Die Statusfarben hängen als fertige Pinsel direkt am Objekt. Das ist
        robuster als Bindungen mit Konvertern, die mit PowerShell-Objekten
        erfahrungsgemäß zickig sind.
    #>
    param($Raw)

    $set = $script:StatusBrushes[$Raw.Status]
    if (-not $set) { $set = $script:StatusBrushes['Error'] }

    [pscustomobject]@{
        Port         = $Raw.Port
        Status       = $Raw.Status
        StatusText   = $script:StatusLabels[$Raw.Status]
        StatusFg     = $set.Fg
        StatusBg     = $set.Bg
        Provider     = $Raw.Provider
        DurationMs   = $Raw.DurationMs
        DurationText = "$($Raw.DurationMs) ms"
        Note         = $Raw.Note
    }
}

function Update-ResultView {
    <#
    .SYNOPSIS
        Baut die sichtbare Liste anhand des gewählten Filters neu auf.
    #>
    $filter = 'Alle'
    if ($ui.CmbFilter.SelectedItem) { $filter = [string]$ui.CmbFilter.SelectedItem }

    $rows = switch ($filter) {
        'Nur offene'       { @($script:RawResults | Where-Object { $_.Status -eq 'Open' }) }
        'Nur geschlossene' { @($script:RawResults | Where-Object { $_.Status -eq 'Closed' }) }
        'Nur Probleme'     { @($script:RawResults | Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'Unknown' }) }
        default            { $script:RawResults.ToArray() }
    }

    $script:ViewRows.Clear()
    foreach ($raw in $rows) { $script:ViewRows.Add((New-ResultRow $raw)) }

    $ui.TxtNoResults.Visibility = if ($script:ViewRows.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    if ($script:RawResults.Count -gt 0 -and $script:ViewRows.Count -eq 0) {
        $ui.TxtNoResults.Text = 'Kein Ergebnis passt zu diesem Filter.'
    } elseif ($script:RawResults.Count -eq 0) {
        $ui.TxtNoResults.Text = 'Noch keine Ergebnisse. Ports eingeben oder oben eine Schnellauswahl anklicken.'
    }
}

function Update-ResultCounters {
    $open   = @($script:RawResults | Where-Object { $_.Status -eq 'Open' }).Count
    $closed = @($script:RawResults | Where-Object { $_.Status -eq 'Closed' }).Count
    $ui.TxtCountOpen.Text   = "$open"
    $ui.TxtCountClosed.Text = "$closed"
    $ui.TxtCountOther.Text  = "$($script:RawResults.Count - $open - $closed)"
}

# ------------------------------------------------------------------------------
# Region: Arbeiter-Skripte (laufen im Hintergrund-Runspace)
# ------------------------------------------------------------------------------

$script:WorkerInit = {
    . $CorePath
    $Sync.Queue.Enqueue(@{ Kind = 'status'; Text = 'Ermittle öffentliche IP...'; Level = 'busy' })
    $publicIp = Get-PublicIPAddress
    $Sync.Queue.Enqueue(@{ Kind = 'public-ip'; Data = $publicIp })
    $overview = Get-NetworkOverview
    $Sync.Queue.Enqueue(@{ Kind = 'network'; Data = $overview })
    $Sync.Queue.Enqueue(@{ Kind = 'done-init' })
}

$script:WorkerPorts = {
    . $CorePath

    $ports   = @($P.Ports)
    $total   = $ports.Count
    $done    = 0
    $failRun = 0

    foreach ($port in $ports) {
        if ($Sync.Cancel) {
            $Sync.Queue.Enqueue(@{ Kind = 'done-ports'; Cancelled = $true; Done = $done; Total = $total })
            return
        }

        $done++
        $Sync.Queue.Enqueue(@{ Kind = 'progress'; Done = $done; Total = $total; Port = $port })

        if ($P.NoListener) {
            $result = Test-PortExternal -Port $port -PublicIP $P.PublicIP -TimeoutSec $P.TimeoutSec -NoListener
        } else {
            $result = Test-PortExternal -Port $port -PublicIP $P.PublicIP -TimeoutSec $P.TimeoutSec
        }
        $Sync.Queue.Enqueue(@{ Kind = 'port-result'; Data = $result })

        if ($result.Status -eq 'Error' -or $result.Status -eq 'Unknown') { $failRun++ } else { $failRun = 0 }

        # Drei Fehlschläge hintereinander deuten auf eine Sperre des Dienstes
        # hin. Dann hilft nur warten - weiterhämmern macht es schlimmer.
        if ($failRun -ge 3) {
            $Sync.Queue.Enqueue(@{ Kind = 'status'
                                   Text = 'Mehrere Fehler in Folge - der Dienst bremst uns aus. Kurze Pause...'
                                   Level = 'warn' })
            $waited = 0
            while ($waited -lt 8000 -and -not $Sync.Cancel) { Start-Sleep -Milliseconds 100; $waited += 100 }
            $failRun = 0
        }

        # Pause zwischen zwei Ports, aber jederzeit abbrechbar
        $waited = 0
        while ($waited -lt $P.DelayMs -and -not $Sync.Cancel) { Start-Sleep -Milliseconds 50; $waited += 50 }
    }

    $Sync.Queue.Enqueue(@{ Kind = 'done-ports'; Cancelled = $false; Done = $done; Total = $total })
}

$script:WorkerNat = {
    . $CorePath
    $report = { param($ServerName) $Sync.Queue.Enqueue(@{ Kind = 'nat-progress'; Text = "Frage $ServerName ..." }) }
    $mappings = Get-StunMappings -TimeoutMs 2500 -OnProgress $report
    $localIp  = Get-LocalPrimaryIP
    $result   = Get-NatAssessment -Mappings $mappings -LocalIP $localIp -PublicIP $P.PublicIP
    $Sync.Queue.Enqueue(@{ Kind = 'nat-done'; Data = $result })
}

$script:WorkerUpnp = {
    . $CorePath
    $Sync.Queue.Enqueue(@{ Kind = 'status'; Text = 'Suche UPnP-Geräte im lokalen Netz...'; Level = 'busy' })
    $devices = Get-UpnpDevices -TimeoutMs 3500
    $Sync.Queue.Enqueue(@{ Kind = 'upnp-done'; Data = @($devices) })
}

$script:WorkerSecurity = {
    . $CorePath
    . $DiagPath

    $ports   = @(Get-SecurityScanPorts)
    $total   = $ports.Count
    $done    = 0
    $failRun = 0

    foreach ($port in $ports) {
        if ($Sync.Cancel) {
            $Sync.Queue.Enqueue(@{ Kind = 'security-done'; Cancelled = $true })
            return
        }
        $done++
        $Sync.Queue.Enqueue(@{ Kind = 'security-progress'; Done = $done; Total = $total; Port = $port })

        if ($P.NoListener) {
            $result = Test-PortExternal -Port $port -PublicIP $P.PublicIP -TimeoutSec $P.TimeoutSec -NoListener
        } else {
            $result = Test-PortExternal -Port $port -PublicIP $P.PublicIP -TimeoutSec $P.TimeoutSec
        }
        $Sync.Queue.Enqueue(@{ Kind = 'security-result'; Data = $result })

        if ($result.Status -eq 'Error' -or $result.Status -eq 'Unknown') { $failRun++ } else { $failRun = 0 }
        if ($failRun -ge 3) {
            $wartete = 0
            while ($wartete -lt 8000 -and -not $Sync.Cancel) { Start-Sleep -Milliseconds 100; $wartete += 100 }
            $failRun = 0
        }
        $wartete = 0
        while ($wartete -lt $P.DelayMs -and -not $Sync.Cancel) { Start-Sleep -Milliseconds 50; $wartete += 50 }
    }
    $Sync.Queue.Enqueue(@{ Kind = 'security-done'; Cancelled = $false })
}

$script:WorkerQuality = {
    . $CorePath
    . $DiagPath

    $ziele = Get-NetworkPathTargets -Gateway $P.Gateway -Dns $P.Dns
    $index = 0
    foreach ($ziel in $ziele) {
        $index++
        $Sync.Queue.Enqueue(@{ Kind = 'quality-progress'; Label = $ziel.Label; Done = $index; Total = @($ziele).Count })
        $messung = Measure-Latency -Target $ziel.Host -Count 10 -PauseMs 100
        $note    = Get-LatencyRating -Measurement $messung
        $Sync.Queue.Enqueue(@{ Kind = 'quality-result'; Target = $ziel; Measure = $messung; Rating = $note })
    }
    $Sync.Queue.Enqueue(@{ Kind = 'quality-done' })
}

$script:WorkerIpv6 = {
    . $CorePath
    . $DiagPath
    $Sync.Queue.Enqueue(@{ Kind = 'status'; Text = 'Prüfe IPv6...'; Level = 'busy' })
    $ergebnis = Get-IPv6Status
    $Sync.Queue.Enqueue(@{ Kind = 'ipv6-done'; Data = $ergebnis })
}

$script:WorkerUpnpConnect = {
    . $CorePath
    . $UpnpPath
    $Sync.Queue.Enqueue(@{ Kind = 'status'; Text = 'Suche Router über UPnP...'; Level = 'busy' })
    $verbindung = Connect-UpnpRouter -TimeoutMs 4000
    $freigaben = @()
    $externeIp = $null
    if ($verbindung.Found) {
        $externeIp = Get-UpnpExternalAddress -ControlPoint $verbindung.ControlPoint
        $freigaben = Get-UpnpPortMappings -ControlPoint $verbindung.ControlPoint
    }
    $Sync.Queue.Enqueue(@{
        Kind = 'upnp-router'; Connection = $verbindung
        Mappings = @($freigaben); ExternalIp = $externeIp
    })
}

$script:WorkerUpnpChange = {
    . $CorePath
    . $UpnpPath
    # Der Steuerpunkt wird bewusst neu ermittelt: das Objekt aus dem
    # Hauptfenster liesse sich zwar übergeben, aber eine frisch geholte
    # Adresse ist verlässlicher, falls der Router zwischenzeitlich neu
    # gestartet hat.
    $verbindung = Connect-UpnpRouter -TimeoutMs 4000
    if (-not $verbindung.Found) {
        $Sync.Queue.Enqueue(@{ Kind = 'upnp-changed'; Success = $false; Message = $verbindung.Message })
        return
    }

    if ($P.Operation -eq 'add') {
        $ergebnis = Add-UpnpPortMapping -ControlPoint $verbindung.ControlPoint `
                        -ExternalPort $P.Port -InternalPort $P.Port `
                        -InternalClient $P.Client -Protocol $P.Protocol -Description $P.Description
    } else {
        $ergebnis = Remove-UpnpPortMapping -ControlPoint $verbindung.ControlPoint `
                        -ExternalPort $P.Port -Protocol $P.Protocol
    }

    $freigaben = Get-UpnpPortMappings -ControlPoint $verbindung.ControlPoint
    $Sync.Queue.Enqueue(@{
        Kind = 'upnp-changed'; Success = $ergebnis.Success; Message = $ergebnis.Message
        Mappings = @($freigaben)
    })
}

$script:WorkerNetwork = {
    . $CorePath
    $overview = Get-NetworkOverview
    $Sync.Queue.Enqueue(@{ Kind = 'network'; Data = $overview })
    $publicIp = Get-PublicIPAddress
    $Sync.Queue.Enqueue(@{ Kind = 'public-ip'; Data = $publicIp })
    $Sync.Queue.Enqueue(@{ Kind = 'done-init' })
}

# ------------------------------------------------------------------------------
# Region: Anzeige der Messergebnisse
# ------------------------------------------------------------------------------

$script:PublicIP        = $null
$script:LastNat         = $null
$script:LastSecurity    = $null
$script:LastIpv6        = $null
$script:StartedAt       = $null
$script:UpnpReady       = $false
$script:UpnpMappings    = @()
$script:SecurityResults = New-Object 'System.Collections.Generic.List[object]'
$script:QualityRows     = New-Object 'System.Collections.Generic.List[object]'

function Show-PublicIp {
    param([string]$Ip)
    $script:PublicIP = $Ip
    if ($Ip) {
        $ui.TxtPublicIp.Text  = $Ip
        $ui.TxtSideIp.Text    = $Ip
        $ui.TxtNetPublic.Text = $Ip
        if (Test-PrivateIPv4 -IPAddress $Ip) {
            $ui.TxtPublicIpNote.Text = 'Achtung: private Adresse - vermutlich CGNAT oder VPN'
        } else {
            $ui.TxtPublicIpNote.Text = 'So sieht dich das Internet'
        }
    } else {
        $ui.TxtPublicIp.Text      = 'nicht ermittelbar'
        $ui.TxtSideIp.Text        = 'nicht ermittelbar'
        $ui.TxtNetPublic.Text     = 'nicht ermittelbar'
        $ui.TxtPublicIpNote.Text  = 'Keine Internetverbindung?'
    }
}

function Show-Network {
    param($Overview)

    $ui.TxtNetHost.Text = $Overview.HostName
    $local = if ($Overview.LocalIPs.Count -gt 0) { $Overview.LocalIPs[0] } else { 'unbekannt' }
    $ui.TxtLocalIp.Text    = $local
    $ui.TxtGateway.Text    = "Router: $(if ($Overview.Gateway) { $Overview.Gateway } else { 'unbekannt' })"
    $ui.TxtNetGateway.Text = if ($Overview.Gateway) { $Overview.Gateway } else { 'unbekannt' }
    $ui.TxtNetDns.Text     = if ($Overview.DnsServers.Count -gt 0) { $Overview.DnsServers -join ', ' } else { 'unbekannt' }

    $rows = foreach ($adapter in $Overview.Adapters) {
        # Bei virtuellen Adaptern wird KEINE Geschwindigkeit angezeigt.
        # Ein WireGuard-Tunnel meldet stur 100 Gbit/s - es gibt keine
        # physische Leitung, deren Tempo man ablesen könnte. Diese Zahl als
        # "deine Geschwindigkeit" hinzustellen wäre schlicht gelogen.
        $tempo = if ($adapter.IsVirtual) {
            'Tunnel - keine echte Leitung'
        } elseif ($adapter.SpeedMbps -gt 0) {
            "$($adapter.SpeedMbps) Mbit/s"
        } else {
            $adapter.Type
        }
        [pscustomobject]@{
            Name        = $adapter.Name
            Description = $adapter.Description
            MacAddress  = $adapter.MacAddress
            IPv4        = $adapter.IPv4
            SpeedText   = $tempo
        }
    }
    $ui.ItemsAdapters.ItemsSource = @($rows)

    # VPN-Hinweis: ändert die Bedeutung jeder Messung in diesem Werkzeug.
    if ($Overview.VpnActive) {
        $ui.VpnWarnCard.Visibility = 'Visible'
        $ui.TxtVpnWarn.Text =
            "Dein Verkehr läuft über den VPN-Tunnel `"$($Overview.VpnName)`". Alle Messungen hier " +
            'beziehen sich damit auf den Ausgang des VPN-Anbieters und NICHT auf deinen eigenen ' +
            'Anschluss: die öffentliche IP gehört dem Anbieter, der Port-Test prüft dessen Server, ' +
            'und der NAT-Typ beschreibt dessen Netz. Für eine Aussage über deinen Router musst du ' +
            'das VPN vorher trennen.'
        $ui.TxtPublicIpNote.Text = "VPN aktiv ($($Overview.VpnName)) - das ist nicht dein Anschluss"
    } else {
        $ui.VpnWarnCard.Visibility = 'Collapsed'
    }
}

function Show-NatResult {
    param($Assessment)

    $script:LastNat = $Assessment
    $ui.TxtNatTitle.Text     = $Assessment.Title
    $ui.TxtNatBehaviour.Text = "Verhalten: $($Assessment.Behaviour)"
    $ui.ItemsNatReasons.ItemsSource = @($Assessment.Reasons)
    $ui.TxtDashNat.Text = $Assessment.Title

    $endpoints = foreach ($mapping in $Assessment.Mappings) {
        [pscustomobject]@{
            Server   = $mapping.Server
            Endpoint = "$($mapping.ExtIP):$($mapping.ExtPort)"
        }
    }
    $ui.LstNatServers.ItemsSource = @($endpoints)
    $ui.TxtNatEmpty.Visibility = if (@($endpoints).Count -eq 0) { 'Visible' } else { 'Collapsed' }
    if (@($endpoints).Count -eq 0) { $ui.TxtNatEmpty.Text = 'Kein STUN-Server hat geantwortet.' }

    $colourKey = switch ($Assessment.Level) {
        'Open'     { 'OkBrush' }
        'Moderate' { 'WarnBrush' }
        'Strict'   { 'BadBrush' }
        default    { 'FgFaintBrush' }
    }
    $glyph = switch ($Assessment.Level) {
        'Open'     { [char]0xE73E }   # Haken
        'Moderate' { [char]0xE7BA }   # Warndreieck
        'Strict'   { [char]0xE711 }   # Kreuz
        default    { [char]0xE9CE }   # Fragezeichen
    }

    $ui.NatBadgeIcon.Text = [string]$glyph
    $ui.NatBadgeText.Text = $Assessment.Title
    $ui.NatBadgeIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $colourKey)
    $ui.NatBadgeText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $colourKey)
    $ui.NatBadge.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, $colourKey)
    $ui.DotNat.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $colourKey)
    $ui.TxtSideNat.Text = "NAT: $($Assessment.Title)"

    $ui.TxtDashNatNote.Text = switch ($Assessment.Level) {
        'Open'     { 'Bestmöglicher Fall' }
        'Moderate' { 'Mit Portfreigabe wird daraus OFFEN' }
        'Strict'   { 'Verbindungsprobleme wahrscheinlich' }
        default    { 'Test im Reiter NAT-Typ' }
    }
}

function Get-ThemeBrush {
    <#
    .SYNOPSIS
        Holt einen Pinsel der aktuellen Farbwelt.
    .DESCRIPTION
        Für Listeneinträge, die ihre Farbe als Objekt mitbringen müssen -
        Bindungen auf Ressourcen funktionieren dort nicht zuverlässig.
    #>
    param([Parameter(Mandatory = $true)][string]$Token)
    return (ConvertTo-PortCheckBrush $script:CurrentTheme.Tokens[$Token])
}

function Show-SecurityResult {
    <#
    .SYNOPSIS
        Zeigt die Bewertung des Sicherheits-Durchlaufs.
    #>
    param($Assessment)

    $script:LastSecurity = $Assessment
    $ui.TxtSecuritySummary.Text = $Assessment.Summary

    $farbe = switch ($Assessment.Level) {
        'Kritisch' { 'BadBrush' }
        'Warnung'  { 'WarnBrush' }
        'Hinweis'  { 'WarnBrush' }
        default    { 'OkBrush' }
    }
    $zeichen = switch ($Assessment.Level) {
        'Kritisch' { [char]0xE7BA }
        'Warnung'  { [char]0xE7BA }
        'Hinweis'  { [char]0xE946 }
        default    { [char]0xE73E }
    }
    $titel = switch ($Assessment.Level) {
        'Kritisch' { 'Handlungsbedarf' }
        'Warnung'  { 'Unnötiges Risiko' }
        'Hinweis'  { 'Kleinigkeiten' }
        default    { 'Unauffällig' }
    }

    $ui.TxtSecurityTitle.Text  = $titel
    $ui.SecurityBadgeText.Text = $Assessment.Level.ToUpper()
    $ui.SecurityBadgeIcon.Text = [string]$zeichen
    $ui.SecurityBadgeIcon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $farbe)
    $ui.SecurityBadgeText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $farbe)
    $ui.SecurityBadge.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, $farbe)

    $zeilen = foreach ($fund in $Assessment.Findings) {
        $token = switch ($fund.Severity) {
            'Kritisch' { 'Bad' }
            'Hoch'     { 'Warn' }
            default    { 'FgDim' }
        }
        $weich = switch ($fund.Severity) {
            'Kritisch' { 'BadSoft' }
            'Hoch'     { 'WarnSoft' }
            default    { 'StrokeSoft' }
        }
        [pscustomobject]@{
            Severity    = $fund.Severity.ToUpper()
            Headline    = "Port $($fund.Port) - $($fund.Name)"
            Why         = $fund.Why
            Accent      = (Get-ThemeBrush $token)
            AccentSoft  = (Get-ThemeBrush $weich)
        }
    }
    $ui.ItemsSecurityFindings.ItemsSource = @($zeilen)
}

function Show-Ipv6Result {
    param($Status)

    $script:LastIpv6 = $Status
    $ui.TxtIpv6Title.Text = $Status.Title
    $ui.ItemsIpv6Reasons.ItemsSource = @($Status.Reasons)

    $farbe = switch ($Status.Level) {
        'Full'    { 'OkBrush' }
        'Partial' { 'WarnBrush' }
        default   { 'FgFaintBrush' }
    }
    $ui.Ipv6Icon.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $farbe)
    $ui.TxtIpv6Title.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $farbe)

    if ($Status.PublicAddress) {
        $ui.TxtIpv6Address.Text = "Deine öffentliche IPv6: $($Status.PublicAddress)"
        $ui.TxtIpv6Address.Visibility = 'Visible'
    } elseif (@($Status.LocalAddresses).Count -gt 0) {
        $ui.TxtIpv6Address.Text = "Lokale IPv6: $(@($Status.LocalAddresses) -join ', ')"
        $ui.TxtIpv6Address.Visibility = 'Visible'
    } else {
        $ui.TxtIpv6Address.Visibility = 'Collapsed'
    }
}

function Show-UpnpMappings {
    <#
    .SYNOPSIS
        Stellt die Portfreigaben des Routers dar und hebt riskante hervor.
    #>
    param([object[]]$Mappings)

    $script:UpnpMappings = @($Mappings)
    $katalog = Get-RiskyPortCatalog

    $zeilen = foreach ($eintrag in $script:UpnpMappings) {
        $risiko = @($katalog | Where-Object { $_.Port -eq $eintrag.ExternalPort })
        $istRisiko = ($risiko.Count -gt 0)
        $token = if ($istRisiko) {
            if ($risiko[0].Severity -eq 'Kritisch') { 'Bad' } else { 'Warn' }
        } else { 'Accent' }
        $weich = if ($istRisiko) {
            if ($risiko[0].Severity -eq 'Kritisch') { 'BadSoft' } else { 'WarnSoft' }
        } else { 'AccentSoft' }

        [pscustomobject]@{
            Key         = "$($eintrag.ExternalPort)/$($eintrag.Protocol)"
            PortText    = "$($eintrag.ExternalPort) $($eintrag.Protocol)"
            Description = $(if ($eintrag.Description) { $eintrag.Description } else { '(ohne Beschreibung)' })
            TargetText  = "$($eintrag.Client):$($eintrag.InternalPort)"
            RiskText    = $(if ($istRisiko) { "Achtung: $($risiko[0].Name) - $($risiko[0].Severity.ToLower())es Risiko" } else { '' })
            RiskVisible = $(if ($istRisiko) { 'Visible' } else { 'Collapsed' })
            Accent      = (Get-ThemeBrush $token)
            AccentSoft  = (Get-ThemeBrush $weich)
        }
    }

    $ui.ItemsUpnpMappings.ItemsSource = @($zeilen)
    $ui.TxtUpnpMappingsEmpty.Visibility =
        if (@($zeilen).Count -eq 0) { 'Visible' } else { 'Collapsed' }
}

function Show-Upnp {
    param([object[]]$Devices)

    $ui.ItemsUpnp.ItemsSource = @($Devices)
    if (@($Devices).Count -gt 0) {
        $ui.TxtUpnpState.Text   = "UPnP verfügbar - $(@($Devices).Count) Gerät(e) haben geantwortet."
        $ui.TxtDashUpnp.Text     = 'verfügbar'
        $ui.TxtDashUpnpNote.Text = 'Spiele können Ports selbst freigeben'
    } else {
        $ui.TxtUpnpState.Text = 'Keine Antwort. UPnP ist im Router deaktiviert, oder der Router antwortet nicht auf SSDP.'
        $ui.TxtDashUpnp.Text     = 'keine Antwort'
        $ui.TxtDashUpnpNote.Text = 'Im Router aktivieren oder Ports von Hand freigeben'
    }
}

# ------------------------------------------------------------------------------
# Region: Warteschlange leeren (läuft im Oberflächen-Thread)
# ------------------------------------------------------------------------------

$script:Pump = New-Object System.Windows.Threading.DispatcherTimer
$script:Pump.Interval = [TimeSpan]::FromMilliseconds(60)

$script:Pump.Add_Tick({
    $message = $null
    $handled = 0

    # Pro Durchlauf begrenzen, damit die Oberfläche bei sehr vielen
    # Nachrichten nicht verhungert.
    while ($handled -lt 250 -and $script:Sync.Queue.TryDequeue([ref]$message)) {
        $handled++
        switch ($message.Kind) {

            'status' {
                $level = if ($message.ContainsKey('Level')) { $message.Level } else { 'idle' }
                Set-Status $message.Text $level
            }

            'public-ip' { Show-PublicIp $message.Data }

            'network'   { Show-Network $message.Data }

            'done-init' {
                # Wichtig: auch der Start-Vorgang muss abgeschlossen werden,
                # sonst gilt die Anwendung weiter als beschäftigt und lehnt die
                # nächste Messung mit "Es läuft bereits eine Messung" ab.
                Complete-Work
                Set-Status 'Bereit.' 'ok'
                # Entwickler-Option -LiveTest: jetzt sind IP und Netzdaten da,
                # also die echte Messung anstossen.
                if ($script:LiveSpec) {
                    Show-Page 'NavPorts'
                    $ui.TxtPortSpec.Text = $script:LiveSpec
                    Start-PortTest $script:LiveSpec
                }
            }

            'progress' {
                $percent = if ($message.Total -gt 0) { 100.0 * $message.Done / $message.Total } else { 0 }
                $ui.ProgPorts.Value  = $percent
                $ui.ProgStatus.Value = $percent
                $ui.TxtPortProgress.Text =
                    "Prüfe Port $($message.Port)  -  $($message.Done) von $($message.Total)"
                Set-Status "Port-Test läuft: $($message.Done)/$($message.Total)" 'busy'
            }

            'port-result' {
                $script:RawResults.Add($message.Data)
                # Nur anhängen statt alles neu aufzubauen - sonst ruckelt es
                # bei langen Listen sichtbar.
                $filter = if ($ui.CmbFilter.SelectedItem) { [string]$ui.CmbFilter.SelectedItem } else { 'Alle' }
                $passes = switch ($filter) {
                    'Nur offene'       { $message.Data.Status -eq 'Open' }
                    'Nur geschlossene' { $message.Data.Status -eq 'Closed' }
                    'Nur Probleme'     { $message.Data.Status -eq 'Error' -or $message.Data.Status -eq 'Unknown' }
                    default            { $true }
                }
                if ($passes) {
                    $script:ViewRows.Add((New-ResultRow $message.Data))
                    $ui.TxtNoResults.Visibility = 'Collapsed'
                }
                Update-ResultCounters
            }

            'done-ports' {
                Complete-Work
                $ui.BtnStart.IsEnabled = $true
                $ui.BtnStop.IsEnabled  = $false
                $ui.ProgPorts.Value    = 100

                $open = @($script:RawResults | Where-Object { $_.Status -eq 'Open' }).Count
                if ($message.Cancelled) {
                    $ui.TxtPortProgress.Text = "Abgebrochen nach $($message.Done) von $($message.Total) Ports."
                    Set-Status 'Test abgebrochen.' 'warn'
                } else {
                    $dauer = if ($script:StartedAt) {
                        ' in ' + ([timespan]::FromSeconds(
                            [math]::Round(((Get-Date) - $script:StartedAt).TotalSeconds))).ToString('hh\:mm\:ss')
                    } else { '' }
                    $ui.TxtPortProgress.Text = "Fertig: $($message.Total) Port(s) geprüft$dauer - $open offen."
                    Set-Status "Fertig. $open von $($message.Total) Port(s) offen." $(if ($open -gt 0) { 'ok' } else { 'warn' })
                }
                Update-ResultView
                Update-ResultCounters

                if ($script:LiveSpec) {
                    # Bericht sammeln statt ausgeben: Ausgaben aus einem
                    # Ereignis-Handler landen NICHT im Konsolenstrom. Deshalb
                    # wird der Bericht erst nach dem Schliessen des Fensters
                    # geschrieben, wenn das Skript wieder normal weiterläuft.
                    $script:LiveReport.Add("Öffentliche IP  = $script:PublicIP")
                    $script:LiveReport.Add("Ergebniszeilen  = $($script:RawResults.Count), davon sichtbar $($script:ViewRows.Count)")
                    foreach ($zeile in $script:ViewRows) {
                        $script:LiveReport.Add(("  Port {0,-6} {1,-8} Anzeige='{2}' Dienst={3} Dauer={4}" -f
                            $zeile.Port, $zeile.Status, $zeile.StatusText, $zeile.Provider, $zeile.DurationText))
                    }
                    $script:LiveReport.Add("Zaehler         = offen $($ui.TxtCountOpen.Text) / zu $($ui.TxtCountClosed.Text) / sonstige $($ui.TxtCountOther.Text)")
                    $script:LiveReport.Add("Statuszeile     = $($ui.TxtStatus.Text)")
                    $script:LiveReport.Add("Fortschritt     = $($ui.TxtPortProgress.Text)")
                    # Abbild und Schliessen bewusst verzögert: WPF muss erst
                    # Layout und Darstellung nachziehen, sonst zeigt das Bild
                    # noch den vorherigen Stand.
                    $nachlauf = New-Object System.Windows.Threading.DispatcherTimer
                    $nachlauf.Interval = [TimeSpan]::FromMilliseconds(700)
                    $nachlauf.Add_Tick({
                        param($sender, $eventArgs)
                        $sender.Stop()
                        if ($script:LiveCapture) {
                            try {
                                Save-WindowImage -Path $script:LiveCapture
                                $script:LiveReport.Add("Abbild          = $script:LiveCapture")
                            } catch {
                                $script:LiveReport.Add("Abbild fehlgeschlagen: $($_.Exception.Message)")
                            }
                        }
                        $script:Win.Close()
                    })
                    $nachlauf.Start()
                }
            }

            'nat-progress' { Set-Status $message.Text 'busy' }

            'nat-done' {
                Complete-Work
                Show-NatResult $message.Data
                $ui.BtnNatStart.IsEnabled = $true
                $ui.BtnNatStart.Content   = 'Erneut messen'
                Set-Status "NAT-Typ: $($message.Data.Title)" $(
                    switch ($message.Data.Level) { 'Open' { 'ok' } 'Moderate' { 'warn' } default { 'error' } })
            }

            'upnp-done' {
                Complete-Work
                Show-Upnp $message.Data
                $ui.BtnUpnpScan.IsEnabled = $true
                Set-Status 'UPnP-Suche beendet.' 'ok'
            }

            'security-progress' {
                $percent = if ($message.Total -gt 0) { 100.0 * $message.Done / $message.Total } else { 0 }
                $ui.ProgSecurity.Value = $percent
                $ui.ProgStatus.Value   = $percent
                $ui.TxtSecurityProgress.Text =
                    "Prüfe Port $($message.Port)  -  $($message.Done) von $($message.Total)"
                Set-Status "Sicherheits-Check: $($message.Done)/$($message.Total)" 'busy'
            }

            'security-result' { $script:SecurityResults.Add($message.Data) }

            'security-done' {
                Complete-Work
                $ui.BtnSecurityScan.IsEnabled = $true
                $ui.BtnSecurityStop.IsEnabled = $false
                $ui.ProgSecurity.Value = 100

                $bewertung = Get-SecurityAssessment -Results $script:SecurityResults.ToArray()
                Show-SecurityResult $bewertung
                if ($message.Cancelled) {
                    $ui.TxtSecurityProgress.Text = 'Abgebrochen - die Bewertung bezieht sich nur auf das bereits Geprüfte.'
                    Set-Status 'Sicherheits-Check abgebrochen.' 'warn'
                } else {
                    $ui.TxtSecurityProgress.Text = "Fertig. $($script:SecurityResults.Count) Risiko-Ports geprüft."
                    Set-Status "Sicherheits-Check fertig: $($bewertung.Level)" $(
                        switch ($bewertung.Level) { 'Sauber' { 'ok' } 'Hinweis' { 'warn' } default { 'error' } })
                }
            }

            'quality-progress' {
                $ui.TxtQualityProgress.Text = "Messe $($message.Label)  -  $($message.Done) von $($message.Total)"
                Set-Status "Verbindungsmessung: $($message.Label)" 'busy'
            }

            'quality-result' {
                $token = switch ($message.Rating.Level) {
                    'Sehr gut'     { 'Ok' }
                    'Gut'          { 'Ok' }
                    'Brauchbar'    { 'Warn' }
                    'Unerreichbar' { 'FgFaint' }
                    default        { 'Bad' }
                }
                $script:QualityRows.Add([pscustomobject]@{
                    Label      = $message.Target.Label
                    HostText   = $message.Target.Host
                    Meaning    = $message.Target.Meaning
                    PingText   = $(if ($message.Measure.Reachable) { "$($message.Measure.AvgMs) ms" } else { '-' })
                    DetailText = $(if ($message.Measure.Reachable) {
                                      "min $($message.Measure.MinMs) / max $($message.Measure.MaxMs) / " +
                                      "Jitter $($message.Measure.JitterMs) / Verlust $($message.Measure.LossPercent) %"
                                  } else { 'keine Antwort' })
                    RatingText = "$($message.Rating.Level) - $($message.Rating.Text)"
                    Accent     = (Get-ThemeBrush $token)
                })
                $ui.ItemsQuality.ItemsSource = $null
                $ui.ItemsQuality.ItemsSource = $script:QualityRows.ToArray()
            }

            'quality-done' {
                Complete-Work
                $ui.BtnQualityStart.IsEnabled = $true
                $ui.TxtQualityProgress.Text = 'Messung abgeschlossen.'
                Set-Status 'Verbindungsmessung fertig.' 'ok'
            }

            'ipv6-done' {
                Complete-Work
                Show-Ipv6Result $message.Data
                $ui.BtnIpv6Check.IsEnabled = $true
                Set-Status "IPv6: $($message.Data.Title)" $(
                    switch ($message.Data.Level) { 'Full' { 'ok' } 'Partial' { 'warn' } default { 'idle' } })
            }

            'upnp-router' {
                Complete-Work
                $ui.BtnUpnpScan.IsEnabled = $true
                $ui.BtnUpnpRefresh.IsEnabled = $true
                if ($message.Connection.Found) {
                    $script:UpnpReady = $true
                    $ui.UpnpManageCard.Visibility = 'Visible'
                    $info = "Router: $($message.Connection.DeviceName)  ($($message.Connection.Address))"
                    if ($message.ExternalIp) { $info += "   -   nach außen: $($message.ExternalIp)" }
                    $ui.TxtUpnpRouterInfo.Text = $info
                    $ui.TxtUpnpState.Text = 'UPnP verfügbar - Freigaben lassen sich hier direkt verwalten.'
                    $ui.TxtDashUpnp.Text = 'verfügbar'
                    $ui.TxtDashUpnpNote.Text = 'Ports lassen sich direkt freigeben'
                    Show-UpnpMappings $message.Mappings
                    Set-Status "UPnP bereit: $($message.Connection.DeviceName)" 'ok'
                } else {
                    $script:UpnpReady = $false
                    $ui.UpnpManageCard.Visibility = 'Collapsed'
                    $ui.TxtUpnpState.Text = $message.Connection.Message
                    $ui.TxtDashUpnp.Text = 'nicht nutzbar'
                    $ui.TxtDashUpnpNote.Text = 'Details im Reiter Netzwerk'
                    Set-Status 'UPnP steht nicht zur Verfügung.' 'warn'
                }
            }

            'upnp-changed' {
                Complete-Work
                $ui.BtnUpnpAdd.IsEnabled = $true
                $ui.BtnUpnpRefresh.IsEnabled = $true
                if ($message.ContainsKey('Mappings')) { Show-UpnpMappings $message.Mappings }
                Set-Status $message.Message $(if ($message.Success) { 'ok' } else { 'error' })
                if (-not $message.Success) {
                    [System.Windows.MessageBox]::Show($message.Message, 'TEE PortChecker', 'OK', 'Warning') | Out-Null
                }
            }
        }
    }

    # Runspace aufräumen, falls der Arbeiter ohne Abschlussnachricht endete
    # (etwa wegen eines unerwarteten Fehlers).
    if ($script:Job -and $script:Job.Handle.IsCompleted -and $script:Sync.Queue.Count -eq 0) {
        Complete-Work
        $ui.BtnStart.IsEnabled    = $true
        $ui.BtnStop.IsEnabled     = $false
        $ui.BtnNatStart.IsEnabled = $true
        $ui.BtnUpnpScan.IsEnabled = $true
    }
})

# ------------------------------------------------------------------------------
# Region: Navigation
# ------------------------------------------------------------------------------

$script:Pages = @{
    'NavDashboard' = 'PageDashboard'
    'NavPorts'     = 'PagePorts'
    'NavPresets'   = 'PagePresets'
    'NavNat'       = 'PageNat'
    'NavHowTo'     = 'PageHowTo'
    'NavSecurity'  = 'PageSecurity'
    'NavQuality'   = 'PageQuality'
    'NavNetwork'   = 'PageNetwork'
    'NavSettings'  = 'PageSettings'
    'NavAbout'     = 'PageAbout'
}

function Show-Page {
    param([string]$NavName)
    foreach ($entry in $script:Pages.GetEnumerator()) {
        $ui[$entry.Value].Visibility = if ($entry.Key -eq $NavName) { 'Visible' } else { 'Collapsed' }
    }
    $ui[$NavName].IsChecked = $true
}

foreach ($navName in $script:Pages.Keys) {
    # Kein .GetNewClosure(): der Handler braucht nichts aus dieser Schleife,
    # er fragt das auslösende Element selbst. Eine Closure würde hier nur
    # die $script:-Ebene verbiegen (siehe Hinweis beim Bild-Timer).
    $ui[$navName].Add_Checked({
        param($sender, $eventArgs)
        Show-Page $sender.Name
    })
}

# ------------------------------------------------------------------------------
# Region: Titelleiste
# ------------------------------------------------------------------------------

$ui.TitleBar.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.ClickCount -eq 2) {
        $script:Win.WindowState = if ($script:Win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
        return
    }
    try { $script:Win.DragMove() } catch { }   # wirft, wenn die Taste schon los ist
})

$ui.BtnMinimize.Add_Click({ $script:Win.WindowState = 'Minimized' })
$ui.BtnMaximize.Add_Click({
    $script:Win.WindowState = if ($script:Win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
})
$ui.BtnClose.Add_Click({ $script:Win.Close() })

$script:Win.Add_StateChanged({
    # Symbol umschalten: Maximieren <-> Wiederherstellen
    $ui.BtnMaximize.Content = if ($script:Win.WindowState -eq 'Maximized') {
        [string][char]0xE923
    } else {
        [string][char]0xE922
    }
})

# ------------------------------------------------------------------------------
# Region: Port-Test
# ------------------------------------------------------------------------------

foreach ($entry in @(
    @{ Text = 'Web (80, 443)';      Spec = '80,443' },
    @{ Text = 'Gaming-Kern';        Spec = '3074,3075,27015,27036' },
    @{ Text = 'Minecraft';          Spec = '25565' },
    @{ Text = 'Steam';              Spec = '27014-27050' },
    @{ Text = 'Systemports 1-1024'; Spec = '1-1024' },
    @{ Text = 'Fernwartung';        Spec = '22,3389,5900' })) {

    $chip = New-Object System.Windows.Controls.Button
    $chip.Content = $entry.Text
    $chip.Style   = $script:Win.FindResource('Chip')
    $chip.Tag     = $entry.Spec
    $chip.Add_Click({
        param($sender, $eventArgs)
        $ui.TxtPortSpec.Text = [string]$sender.Tag
    })
    [void]$ui.PanelChips.Children.Add($chip)
}

function Start-PortTest {
    <#
    .SYNOPSIS
        Prüft die Eingabe und startet den Port-Test.
    #>
    param([string]$Spec)

    if (-not $script:PublicIP) {
        [System.Windows.MessageBox]::Show(
            'Die öffentliche IP ist noch nicht bekannt. Ohne sie kann von außen nicht geprüft werden.' +
            "`n`nBesteht eine Internetverbindung? Über 'Werte neu laden' auf der Übersicht lässt sich das wiederholen.",
            'TEE PortChecker', 'OK', 'Warning') | Out-Null
        return
    }

    $parsed = ConvertFrom-PortSpec -Spec $Spec
    if ($parsed.Invalid.Count -gt 0) {
        [System.Windows.MessageBox]::Show(
            "Diese Eingaben wurden nicht verstanden und übersprungen:`n  " +
            ($parsed.Invalid -join ', ') +
            "`n`nErlaubt sind einzelne Ports (80), Bereiche (1-1024) und Listen (80,443,3074).",
            'TEE PortChecker', 'OK', 'Warning') | Out-Null
    }
    if ($parsed.Ports.Count -eq 0) {
        Set-Status 'Keine gültigen Ports angegeben.' 'warn'
        return
    }

    if ($script:Settings.WarnLarge -and $parsed.Ports.Count -gt 50) {
        $seconds  = [math]::Round($parsed.Ports.Count * (($script:Settings.DelayMs / 1000.0) + 1.3))
        $estimate = [timespan]::FromSeconds($seconds).ToString('hh\:mm\:ss')
        $answer = [System.Windows.MessageBox]::Show(
            "$($parsed.Ports.Count) Ports werden geprüft. Geschätzte Dauer: ca. $estimate.`n`n" +
            "Der externe Dienst begrenzt die Anfragen - schneller geht es nicht, ohne gesperrt zu werden.`n`n" +
            'Wirklich starten?',
            'TEE PortChecker', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { return }
    }

    $script:RawResults.Clear()
    $script:ViewRows.Clear()
    Update-ResultCounters
    $ui.ProgPorts.Value = 0
    $ui.TxtNoResults.Visibility = 'Collapsed'
    $script:StartedAt = Get-Date

    $started = Start-Work -Body $script:WorkerPorts -Parameters @{
        Ports      = $parsed.Ports
        PublicIP   = $script:PublicIP
        DelayMs    = [int]$script:Settings.DelayMs
        TimeoutSec = [int]$script:Settings.TimeoutSec
        NoListener = -not [bool]$script:Settings.UseListener
    }
    if ($started) {
        $ui.BtnStart.IsEnabled = $false
        $ui.BtnStop.IsEnabled  = $true
        Set-Status "Port-Test gestartet ($($parsed.Ports.Count) Ports)." 'busy'
        $script:Settings.LastPorts = $Spec
        Export-AppSettings
    }
}

$ui.BtnStart.Add_Click({ Start-PortTest $ui.TxtPortSpec.Text })
$ui.BtnStop.Add_Click({ Stop-Work })
$ui.TxtPortSpec.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq 'Return' -and $ui.BtnStart.IsEnabled) { Start-PortTest $ui.TxtPortSpec.Text }
})

foreach ($option in @('Alle', 'Nur offene', 'Nur geschlossene', 'Nur Probleme')) {
    [void]$ui.CmbFilter.Items.Add($option)
}
$ui.CmbFilter.SelectedIndex = 0
$ui.CmbFilter.Add_SelectionChanged({ Update-ResultView })

$ui.BtnClearResults.Add_Click({
    $script:RawResults.Clear()
    $script:ViewRows.Clear()
    Update-ResultCounters
    Update-ResultView
    $ui.ProgPorts.Value = 0
    $ui.TxtPortProgress.Text = 'Bereit.'
    Set-Status 'Ergebnisse geleert.' 'idle'
})

$ui.BtnCopyOpen.Add_Click({
    $open = @($script:RawResults | Where-Object { $_.Status -eq 'Open' } | ForEach-Object { $_.Port })
    if ($open.Count -eq 0) {
        Set-Status 'Es gibt keine offenen Ports zum Kopieren.' 'warn'
        return
    }
    [System.Windows.Clipboard]::SetText((ConvertTo-PortSpec -Ports $open))
    Set-Status "$($open.Count) offene Port(s) in die Zwischenablage kopiert." 'ok'
})

$ui.BtnExport.Add_Click({
    if ($script:RawResults.Count -eq 0) {
        Set-Status 'Nichts zu exportieren.' 'warn'
        return
    }
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = 'CSV-Tabelle (*.csv)|*.csv|JSON (*.json)|*.json|Textbericht (*.txt)|*.txt'
    $dialog.FileName = 'portcheck_{0:yyyy-MM-dd_HHmm}' -f (Get-Date)
    if ($dialog.ShowDialog() -ne $true) { return }

    $format = switch ([System.IO.Path]::GetExtension($dialog.FileName).ToLower()) {
        '.json' { 'json' }
        '.txt'  { 'txt' }
        default { 'csv' }
    }
    try {
        Export-PortCheckResult -Results $script:RawResults.ToArray() -Path $dialog.FileName `
                               -Format $format -PublicIP $script:PublicIP
        Set-Status "Gespeichert: $($dialog.FileName)" 'ok'
    } catch {
        Set-Status "Speichern fehlgeschlagen: $($_.Exception.Message)" 'error'
    }
})

# ------------------------------------------------------------------------------
# Region: Presets
# ------------------------------------------------------------------------------

$script:AllPresets  = @(Get-PortCheckPresets)
$script:PresetViews = @()

function Initialize-PresetViews {
    <#
    .SYNOPSIS
        Erzeugt die Anzeigeobjekte für die Preset-Karten.
    #>
    $views = foreach ($preset in $script:AllPresets) {
        $resolved = Resolve-PresetPorts -Preset $preset -AllPresets $script:AllPresets

        $sub = @($preset.Vendor, $preset.Platform) | Where-Object { $_ }
        if ($preset.Year -gt 0) { $sub += "$($preset.Year)" }

        $tip = "TCP: $(ConvertTo-PortSpec -Ports $resolved.TCP)"
        if ($resolved.UDP.Count -gt 0) { $tip += "`nUDP: $(ConvertTo-PortSpec -Ports $resolved.UDP)" }
        if ($resolved.BaseName)        { $tip += "`n`nEnthält die Basisports von: $($resolved.BaseName)" }
        if ($preset.Note)              { $tip += "`n`n$($preset.Note)" }
        if ($preset.Source)            { $tip += "`n`nQuelle: $($preset.Source)" }

        [pscustomobject]@{
            Id         = $preset.Id
            Name       = $preset.Name
            Category   = $preset.Category
            SubText    = ($sub -join '  -  ')
            TcpText    = "TCP $($resolved.TCP.Count)"
            UdpText    = "UDP $($resolved.UDP.Count)"
            Tip        = $tip
            Tcp        = $resolved.TCP
            Udp        = $resolved.UDP
            SearchText = ("$($preset.Name) $($preset.Vendor) $($preset.Platform) $($preset.Category)").ToLower()
            IsSelected = $false
        }
    }
    $script:PresetViews = @($views)
}

function Update-PresetList {
    <#
    .SYNOPSIS
        Filtert die Karten nach Kategorie und Suchtext.
    #>
    $category = if ($ui.CmbCategory.SelectedItem) { [string]$ui.CmbCategory.SelectedItem } else { 'Alle Kategorien' }
    $search   = $ui.TxtPresetSearch.Text.Trim().ToLower()

    $shown = @($script:PresetViews | Where-Object {
        ($category -eq 'Alle Kategorien' -or $_.Category -eq $category) -and
        ($search -eq '' -or $_.SearchText -like "*$search*")
    })

    $ui.ItemsPresets.ItemsSource = $shown
    $ui.TxtPresetIntro.Text =
        "$($shown.Count) von $($script:PresetViews.Count) Einträgen. Portlisten aus den offiziellen Hersteller-Angaben; " +
        'Konsolen-Einträge enthalten automatisch die Basisports der Plattform.'
}

function Update-PresetSelection {
    $selected = @($script:PresetViews | Where-Object { $_.IsSelected })

    if ($selected.Count -eq 0) {
        $ui.TxtPresetSelection.Text  = 'Nichts ausgewählt.'
        $ui.TxtPresetUdp.Text        = ''
        $ui.BtnPresetTest.IsEnabled  = $false
        return
    }

    $tcp = New-Object 'System.Collections.Generic.SortedSet[int]'
    $udp = New-Object 'System.Collections.Generic.SortedSet[int]'
    foreach ($view in $selected) {
        foreach ($port in $view.Tcp) { [void]$tcp.Add($port) }
        foreach ($port in $view.Udp) { [void]$udp.Add($port) }
    }

    $names = ($selected | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
    if ($selected.Count -gt 3) { $names += " und $($selected.Count - 3) weitere" }

    $ui.TxtPresetSelection.Text = "$names  -  $($tcp.Count) TCP-Ports werden geprüft."
    $ui.TxtPresetUdp.Text = if ($udp.Count -gt 0) {
        "UDP $(ConvertTo-PortSpec -Ports @($udp)) - von außen nicht prüfbar, aber im Router freizugeben."
    } else { '' }
    $ui.BtnPresetTest.IsEnabled = $true
}

Initialize-PresetViews

[void]$ui.CmbCategory.Items.Add('Alle Kategorien')
foreach ($category in (Get-PresetCategories)) { [void]$ui.CmbCategory.Items.Add($category) }
$ui.CmbCategory.SelectedIndex = 0
$ui.CmbCategory.Add_SelectionChanged({ Update-PresetList })
$ui.TxtPresetSearch.Add_TextChanged({ Update-PresetList })

# Die Karten sind ToggleButtons in einer Vorlage - deren Ereignisse steigen
# bis zum ItemsControl auf, dort fängt ein Handler sie zentral ab.
$ui.ItemsPresets.AddHandler(
    [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
    [System.Windows.RoutedEventHandler]{ Update-PresetSelection })
$ui.ItemsPresets.AddHandler(
    [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
    [System.Windows.RoutedEventHandler]{ Update-PresetSelection })

$ui.BtnPresetClear.Add_Click({
    foreach ($view in $script:PresetViews) { $view.IsSelected = $false }
    Update-PresetList          # neu binden, damit die Karten sich abwählen
    Update-PresetSelection
})

$ui.BtnPresetTest.Add_Click({
    $selected = @($script:PresetViews | Where-Object { $_.IsSelected })
    if ($selected.Count -eq 0) { return }

    $tcp = New-Object 'System.Collections.Generic.SortedSet[int]'
    foreach ($view in $selected) { foreach ($port in $view.Tcp) { [void]$tcp.Add($port) } }

    $ui.TxtPortSpec.Text = ConvertTo-PortSpec -Ports @($tcp)
    Show-Page 'NavPorts'
    Start-PortTest $ui.TxtPortSpec.Text
})

Update-PresetList
Update-PresetSelection

# ------------------------------------------------------------------------------
# Region: NAT-Test
# ------------------------------------------------------------------------------

$ui.BtnNatStart.Add_Click({
    $started = Start-Work -Body $script:WorkerNat -Parameters @{ PublicIP = $script:PublicIP }
    if ($started) {
        $ui.BtnNatStart.IsEnabled = $false
        $ui.TxtNatTitle.Text      = 'Messung läuft...'
        $ui.TxtNatBehaviour.Text  = 'Es werden mehrere STUN-Server befragt (ca. 5-15 Sekunden).'
        Set-Status 'NAT-Messung läuft...' 'busy'
    }
})

$ui.BtnNatCopy.Add_Click({
    if (-not $script:LastNat) {
        Set-Status 'Es gibt noch kein Ergebnis zum Kopieren.' 'warn'
        return
    }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add("PortCheck - NAT-Bericht vom $((Get-Date).ToString('yyyy-MM-dd HH:mm'))")
    $lines.Add("Einstufung: $($script:LastNat.Title)")
    $lines.Add("Verhalten:  $($script:LastNat.Behaviour)")
    $lines.Add("Lokale IP:  $($script:LastNat.LocalIP)")
    $lines.Add("Externe IP: $($script:LastNat.ExternalIP)")
    $lines.Add('')
    foreach ($mapping in $script:LastNat.Mappings) {
        $lines.Add("  $($mapping.Server) sieht dich als $($mapping.ExtIP):$($mapping.ExtPort)")
    }
    $lines.Add('')
    foreach ($reason in $script:LastNat.Reasons) { $lines.Add("- $reason") }

    [System.Windows.Clipboard]::SetText(($lines -join [Environment]::NewLine))
    Set-Status 'NAT-Bericht in die Zwischenablage kopiert.' 'ok'
})

# ------------------------------------------------------------------------------
# Region: Netzwerk
# ------------------------------------------------------------------------------

$ui.BtnUpnpScan.Add_Click({
    # Sucht den Router UND holt gleich die vorhandenen Freigaben - das ist
    # der Zustand, den man eigentlich sehen will.
    $started = Start-Work -Body $script:WorkerUpnpConnect
    if ($started) {
        $ui.BtnUpnpScan.IsEnabled = $false
        $ui.TxtUpnpState.Text     = 'Suche läuft...'
    }
})

$ui.BtnNetRefresh.Add_Click({
    if (Start-Work -Body $script:WorkerNetwork) { Set-Status 'Netzwerkdaten werden neu geladen...' 'busy' }
})

# ------------------------------------------------------------------------------
# Region: Sicherheits-Check
# ------------------------------------------------------------------------------

$ui.BtnSecurityScan.Add_Click({
    if (-not $script:PublicIP) {
        Set-Status 'Die öffentliche IP ist noch nicht bekannt.' 'warn'
        return
    }
    $anzahl = @(Get-SecurityScanPorts).Count
    $sekunden = [math]::Round($anzahl * (($script:Settings.DelayMs / 1000.0) + 1.3))
    $dauer = [timespan]::FromSeconds($sekunden).ToString('hh\:mm\:ss')
    $antwort = [System.Windows.MessageBox]::Show(
        "Es werden $anzahl bekannte Risiko-Ports geprüft. Geschätzte Dauer: ca. $dauer.`n`n" +
        "Dabei wird für jeden Port kurz ein lokaler Listener geöffnet - Windows fragt " +
        "gegebenenfalls nach einer Firewall-Freigabe.`n`nStarten?",
        'TEE PortChecker', 'YesNo', 'Question')
    if ($antwort -ne 'Yes') { return }

    $script:SecurityResults.Clear()
    $ui.ItemsSecurityFindings.ItemsSource = $null
    $ui.ProgSecurity.Value = 0

    $gestartet = Start-Work -Body $script:WorkerSecurity -Parameters @{
        PublicIP   = $script:PublicIP
        DelayMs    = [int]$script:Settings.DelayMs
        TimeoutSec = [int]$script:Settings.TimeoutSec
        NoListener = -not [bool]$script:Settings.UseListener
    }
    if ($gestartet) {
        $ui.BtnSecurityScan.IsEnabled = $false
        $ui.BtnSecurityStop.IsEnabled = $true
        $ui.TxtSecurityTitle.Text = 'Prüfung läuft...'
        Set-Status 'Sicherheits-Check gestartet.' 'busy'
    }
})

$ui.BtnSecurityStop.Add_Click({ Stop-Work })

# ------------------------------------------------------------------------------
# Region: Verbindungsqualität
# ------------------------------------------------------------------------------

$ui.BtnQualityStart.Add_Click({
    $script:QualityRows.Clear()
    $ui.ItemsQuality.ItemsSource = $null
    $dns = $ui.TxtNetDns.Text
    if ($dns -and $dns -ne '...' -and $dns -ne 'unbekannt') { $dns = ($dns -split ',')[0].Trim() } else { $dns = '' }
    $gateway = $ui.TxtNetGateway.Text
    if ($gateway -eq '...' -or $gateway -eq 'unbekannt') { $gateway = '' }

    $gestartet = Start-Work -Body $script:WorkerQuality -Parameters @{ Gateway = $gateway; Dns = $dns }
    if ($gestartet) {
        $ui.BtnQualityStart.IsEnabled = $false
        $ui.TxtQualityProgress.Text = 'Messung läuft...'
        Set-Status 'Verbindungsmessung läuft...' 'busy'
    }
})

$ui.BtnQualityCopy.Add_Click({
    if ($script:QualityRows.Count -eq 0) {
        Set-Status 'Es gibt noch keine Messung zum Kopieren.' 'warn'
        return
    }
    $zeilen = New-Object 'System.Collections.Generic.List[string]'
    $zeilen.Add("TEE PortChecker - Verbindungsqualität vom $((Get-Date).ToString('yyyy-MM-dd HH:mm'))")
    $zeilen.Add('')
    foreach ($z in $script:QualityRows) {
        $zeilen.Add(("{0,-18} {1,-16} {2,8}   {3}" -f $z.Label, $z.HostText, $z.PingText, $z.DetailText))
        $zeilen.Add("                   -> $($z.RatingText)")
    }
    $zeilen.Add('')
    $zeilen.Add('Gemessen mit TEE PortChecker - linktr.ee/theersysending')
    [System.Windows.Clipboard]::SetText(($zeilen -join [Environment]::NewLine))
    Set-Status 'Bericht in die Zwischenablage kopiert.' 'ok'
})

# ------------------------------------------------------------------------------
# Region: IPv6
# ------------------------------------------------------------------------------

$ui.BtnIpv6Check.Add_Click({
    if (Start-Work -Body $script:WorkerIpv6) {
        $ui.BtnIpv6Check.IsEnabled = $false
        $ui.TxtIpv6Title.Text = 'Prüfung läuft...'
    }
})

# ------------------------------------------------------------------------------
# Region: UPnP-Freigaben verwalten
# ------------------------------------------------------------------------------

foreach ($eintrag in @('TCP', 'UDP')) { [void]$ui.CmbUpnpProtocol.Items.Add($eintrag) }
$ui.CmbUpnpProtocol.SelectedIndex = 0

$ui.BtnUpnpRefresh.Add_Click({
    if (Start-Work -Body $script:WorkerUpnpConnect) {
        $ui.BtnUpnpRefresh.IsEnabled = $false
        Set-Status 'Frage Router ab...' 'busy'
    }
})

$ui.BtnUpnpAdd.Add_Click({
    $zerlegt = ConvertFrom-PortSpec -Spec $ui.TxtUpnpPort.Text
    if ($zerlegt.Ports.Count -ne 1) {
        Set-Status 'Bitte genau eine Portnummer eintragen.' 'warn'
        return
    }
    $port = $zerlegt.Ports[0]
    $protokoll = [string]$ui.CmbUpnpProtocol.SelectedItem
    $beschreibung = $ui.TxtUpnpDescription.Text.Trim()
    if (-not $beschreibung) { $beschreibung = 'TEE PortChecker' }

    $lokal = $ui.TxtLocalIp.Text
    if (-not $lokal -or $lokal -eq '...' -or $lokal -eq 'unbekannt') {
        Set-Status 'Die lokale IP ist noch nicht bekannt.' 'warn'
        return
    }

    # Vor dem Öffnen eines Wegs aus dem Internet ausdrücklich nachfragen -
    # und wenn der Port als riskant bekannt ist, das auch deutlich sagen.
    $warnung = ''
    $risiko = @(Get-RiskyPortCatalog | Where-Object { $_.Port -eq $port })
    if ($risiko.Count -gt 0) {
        $warnung = "`n`nACHTUNG: Port $port ($($risiko[0].Name)) gilt als $($risiko[0].Severity.ToLower())es Risiko.`n" +
                   "$($risiko[0].Why)"
    }

    $antwort = [System.Windows.MessageBox]::Show(
        "Port $port/$protokoll wird im Router auf $lokal freigegeben.`n`n" +
        "Damit ist dieser Rechner auf diesem Port aus dem Internet erreichbar." +
        "$warnung`n`nWirklich freigeben?",
        'TEE PortChecker', 'YesNo', $(if ($risiko.Count -gt 0) { 'Warning' } else { 'Question' }))
    if ($antwort -ne 'Yes') { return }

    $gestartet = Start-Work -Body $script:WorkerUpnpChange -Parameters @{
        Operation = 'add'; Port = $port; Protocol = $protokoll
        Client = $lokal; Description = $beschreibung
    }
    if ($gestartet) {
        $ui.BtnUpnpAdd.IsEnabled = $false
        $ui.BtnUpnpRefresh.IsEnabled = $false
        Set-Status "Lege Freigabe für Port $port/$protokoll an..." 'busy'
    }
})

# Die Entfernen-Knöpfe stecken in der Vorlage der Liste. Ihr Klick steigt bis
# zum ItemsControl auf, dort wird er zentral abgefangen - so braucht es keinen
# Handler je Zeile.
$ui.ItemsUpnpMappings.AddHandler(
    [System.Windows.Controls.Button]::ClickEvent,
    [System.Windows.RoutedEventHandler]{
        param($sender, $eventArgs)
        $knopf = $eventArgs.OriginalSource
        if (-not ($knopf -is [System.Windows.Controls.Button])) { return }
        $schluessel = [string]$knopf.Tag
        if (-not $schluessel) { return }

        $teile = $schluessel -split '/'
        if ($teile.Count -ne 2) { return }
        $port = [int]$teile[0]
        $protokoll = $teile[1]

        $antwort = [System.Windows.MessageBox]::Show(
            "Freigabe für Port $port/$protokoll aus dem Router entfernen?",
            'TEE PortChecker', 'YesNo', 'Question')
        if ($antwort -ne 'Yes') { return }

        if (Start-Work -Body $script:WorkerUpnpChange -Parameters @{
                Operation = 'remove'; Port = $port; Protocol = $protokoll }) {
            $ui.BtnUpnpAdd.IsEnabled = $false
            $ui.BtnUpnpRefresh.IsEnabled = $false
            Set-Status "Entferne Freigabe für Port $port/$protokoll..." 'busy'
        }
    })

# ------------------------------------------------------------------------------
# Region: Übersicht
# ------------------------------------------------------------------------------

$ui.BtnQuickNat.Add_Click({
    Show-Page 'NavNat'
    $ui.BtnNatStart.RaiseEvent(
        (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
})
$ui.BtnQuickPresets.Add_Click({ Show-Page 'NavPresets' })

# ------------------------------------------------------------------------------
# Region: Seite "Ports öffnen"
# ------------------------------------------------------------------------------

$ui.BtnHowToTest.Add_Click({ Show-Page 'NavPorts' })

$ui.BtnOpenRouter.Add_Click({
    # Öffnet die Weboberfläche des Routers - also die Adresse des
    # Standard-Gateways. Die steht nach dem Start bereits fest.
    $gateway = $ui.TxtNetGateway.Text
    if (-not $gateway -or $gateway -eq '...' -or $gateway -eq 'unbekannt') {
        Set-Status 'Die Router-Adresse ist noch nicht bekannt - kurz warten oder im Reiter Netzwerk aktualisieren.' 'warn'
        return
    }
    if (Open-ExternalLink "http://$gateway") {
        Set-Status "Router-Oberfläche wird geöffnet: http://$gateway" 'ok'
    } else {
        Set-Status 'Der Browser ließ sich nicht öffnen.' 'warn'
    }
})
$ui.BtnQuickRefresh.Add_Click({
    if (Start-Work -Body $script:WorkerNetwork) { Set-Status 'Werte werden neu geladen...' 'busy' }
})

# ------------------------------------------------------------------------------
# Region: Einstellungen
# ------------------------------------------------------------------------------

$script:ThemeViews = @(foreach ($themeItem in $script:Themes) {
    [pscustomobject]@{
        Id            = $themeItem.Id
        Name          = $themeItem.Name
        Tagline       = $themeItem.Tagline
        SwatchBg      = (ConvertTo-PortCheckBrush $themeItem.Tokens['Card'])
        SwatchStroke  = (ConvertTo-PortCheckBrush $themeItem.Tokens['Stroke'])
        SwatchAccent  = (ConvertTo-PortCheckBrush $themeItem.Tokens['Accent'])
        SwatchAccent2 = (ConvertTo-PortCheckBrush $themeItem.Tokens['Accent2'])
        IsSelected    = ($themeItem.Id -eq $script:CurrentTheme.Id)
    }
})
$ui.ItemsThemes.ItemsSource = $script:ThemeViews

$ui.ItemsThemes.AddHandler(
    [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
    [System.Windows.RoutedEventHandler]{
        param($sender, $eventArgs)
        $view = $eventArgs.OriginalSource.DataContext
        if ($view -and $view.Id -ne $script:CurrentTheme.Id) {
            Switch-AppTheme (Get-ThemeById $view.Id)
            Set-Status "Farbwelt: $($view.Name)" 'ok'
        }
    })

$ui.SldDelay.Value = [double]$script:Settings.DelayMs
$ui.SldDelay.Add_ValueChanged({
    $value = [int]$ui.SldDelay.Value
    $ui.TxtDelayValue.Text = "$value ms"
    $script:Settings.DelayMs = $value
    Export-AppSettings
})
$ui.TxtDelayValue.Text = "$([int]$script:Settings.DelayMs) ms"

$ui.SldTimeout.Value = [double]$script:Settings.TimeoutSec
$ui.SldTimeout.Add_ValueChanged({
    $value = [int]$ui.SldTimeout.Value
    $ui.TxtTimeoutValue.Text = "$value s"
    $script:Settings.TimeoutSec = $value
    Export-AppSettings
})
$ui.TxtTimeoutValue.Text = "$([int]$script:Settings.TimeoutSec) s"

$ui.ChkListener.IsChecked = [bool]$script:Settings.UseListener
$ui.ChkListener.Add_Click({
    $script:Settings.UseListener = [bool]$ui.ChkListener.IsChecked
    Export-AppSettings
})

$ui.ChkWarnLarge.IsChecked = [bool]$script:Settings.WarnLarge
$ui.ChkWarnLarge.Add_Click({
    $script:Settings.WarnLarge = [bool]$ui.ChkWarnLarge.IsChecked
    Export-AppSettings
})

$ui.TxtSettingsPath.Text =
    "Einstellungen liegen in: $script:SettingsFile" + [Environment]::NewLine +
    'Es wird nichts anderes gespeichert - keine Messergebnisse, keine IP-Adressen, keine Verlaufsdaten.'

$ui.BtnOpenSettingsFolder.Add_Click({
    try {
        if (-not (Test-Path $script:SettingsDir)) {
            New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        }
        Start-Process explorer.exe $script:SettingsDir
    } catch {
        Set-Status "Ordner ließ sich nicht öffnen: $($_.Exception.Message)" 'error'
    }
})

$ui.BtnResetSettings.Add_Click({
    $answer = [System.Windows.MessageBox]::Show(
        'Alle Einstellungen auf die Standardwerte zurücksetzen?',
        'TEE PortChecker', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }

    $script:Settings = Get-DefaultSettings
    Export-AppSettings
    $ui.SldDelay.Value        = [double]$script:Settings.DelayMs
    $ui.SldTimeout.Value      = [double]$script:Settings.TimeoutSec
    $ui.ChkListener.IsChecked = [bool]$script:Settings.UseListener
    $ui.ChkWarnLarge.IsChecked= [bool]$script:Settings.WarnLarge
    foreach ($view in $script:ThemeViews) { $view.IsSelected = ($view.Id -eq $script:Settings.Theme) }
    $ui.ItemsThemes.ItemsSource = $null
    $ui.ItemsThemes.ItemsSource = $script:ThemeViews
    Switch-AppTheme (Get-ThemeById $script:Settings.Theme)
    Set-Status 'Einstellungen zurückgesetzt.' 'ok'
})

# ------------------------------------------------------------------------------
# Region: Über
# ------------------------------------------------------------------------------

$ui.TxtVersionChip.Text  = "v$script:AppVersion"
$ui.TxtAboutVersion.Text = "$script:AppName $script:AppVersion  -  läuft auf PowerShell $($PSVersionTable.PSVersion)"
$ui.TxtRepoShort.Text    = $script:RepoUrl -replace '^https://', ''

$ui.BtnOpenRepo.Add_Click({
    if (-not (Open-ExternalLink $script:RepoUrl)) { Set-Status 'Browser ließ sich nicht öffnen.' 'warn' }
})
$ui.BtnOpenSource.Add_Click({
    try { Start-Process explorer.exe $script:Root } catch { }
})

# ------------------------------------------------------------------------------
# Region: Verweise nach draußen
# ------------------------------------------------------------------------------

# Zuordnung Schaltfläche -> Adresse. Bewusst über den Elementnamen und NICHT
# über .Tag: Tag trägt bei diesen Schaltflächen bereits das Symbolzeichen der
# Vorlage. Und bewusst ohne .GetNewClosure(), weil das die $script:-Ebene
# verbiegen würde - der Handler fragt stattdessen das auslösende Element.
$script:LinkMap = @{
    'BtnLinktree'      = @{ Url = $script:LinktreeUrl; Text = 'linktr.ee wird im Browser geöffnet.' }
    'BtnAboutLinktree' = @{ Url = $script:LinktreeUrl; Text = 'linktr.ee wird im Browser geöffnet.' }
    'BtnWelcomeLink'   = @{ Url = $script:LinktreeUrl; Text = 'linktr.ee wird im Browser geöffnet.' }
    'BtnDiscord'       = @{ Url = $script:DiscordUrl;  Text = 'Discord-Einladung wird geöffnet.' }
    'BtnAboutDiscord'  = @{ Url = $script:DiscordUrl;  Text = 'Discord-Einladung wird geöffnet.' }
    'BtnSideDiscord'   = @{ Url = $script:DiscordUrl;  Text = 'Discord-Einladung wird geöffnet.' }
    'BtnAboutRepo'     = @{ Url = $script:RepoUrl;     Text = 'Projektseite wird geöffnet.' }
    'BtnSideLinktree'  = @{ Url = $script:LinktreeUrl; Text = 'linktr.ee wird im Browser geöffnet.' }
    'BtnPureVpn'       = @{ Url = $script:PureVpnUrl;  Text = 'PureVPN wird im Browser geöffnet (Empfehlungslink).' }
}

foreach ($linkName in @('BtnLinktree', 'BtnAboutLinktree', 'BtnDiscord',
                        'BtnAboutDiscord', 'BtnSideDiscord', 'BtnSideLinktree',
                        'BtnAboutRepo', 'BtnPureVpn')) {
    $ui[$linkName].Add_Click({
        param($sender, $eventArgs)
        $ziel = $script:LinkMap[$sender.Name]
        if (-not $ziel) { return }
        if (Open-ExternalLink $ziel.Url) {
            Set-Status $ziel.Text 'ok'
        } else {
            Set-Status 'Der Browser ließ sich nicht öffnen.' 'warn'
        }
    })
}

# ------------------------------------------------------------------------------
# Region: Willkommensfenster
# ------------------------------------------------------------------------------

function Show-WelcomeWindow {
    <#
    .SYNOPSIS
        Zeigt das Willkommensfenster als modales Fenster über der Anwendung.
    .DESCRIPTION
        Es wird bei jedem Aufruf frisch aufgebaut. Das kostet ein paar
        Millisekunden, spart aber Zustand: das Fenster erscheint im Normalfall
        genau einmal im Leben der Installation.
    #>
    [CmdletBinding()]
    param()

    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load($script:WelcomePath)
        $fenster = [System.Windows.Markup.XamlReader]::Load(
            (New-Object System.Xml.XmlNodeReader -ArgumentList $doc))
    } catch {
        Set-Status "Willkommensfenster ließ sich nicht laden: $($_.Exception.Message)" 'warn'
        return
    }

    # Eigenes Fenster, eigene Ressourcen - deshalb das Theme hier erneut
    # eintragen.
    Set-PortCheckTheme -Window $fenster -Theme $script:CurrentTheme
    # Beim Abbild-Lauf ist das Hauptfenster nicht sichtbar - dann darf es auch
    # nicht als Eigentümer gesetzt werden, sonst wirft WPF.
    if (-not $script:WelcomeCapture) { $fenster.Owner = $script:Win }

    $fenster.FindName('TxtWelcomeVersion').Text = "Version $script:AppVersion"

    $fenster.FindName('WelcomeTitleBar').Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        try { [System.Windows.Window]::GetWindow($sender).DragMove() } catch { }
    })

    $schliessen = {
        param($sender, $eventArgs)
        [System.Windows.Window]::GetWindow($sender).Close()
    }
    $fenster.FindName('BtnWelcomeClose').Add_Click($schliessen)
    $fenster.FindName('BtnWelcomeStart').Add_Click($schliessen)

    # Die beiden Verweise. Auch hier ohne Closure - die Adresse hängt am
    # Element, das Symbol steckt in Tag und bleibt unangetastet.
    $discord = $fenster.FindName('BtnWelcomeDiscord')
    $discord.DataContext = $script:DiscordUrl
    $discord.Add_Click({
        param($sender, $eventArgs)
        [void](Open-ExternalLink ([string]$sender.DataContext))
    })

    $linktree = $fenster.FindName('BtnWelcomeLinktree')
    $linktree.DataContext = $script:LinktreeUrl
    $linktree.Add_Click({
        param($sender, $eventArgs)
        [void](Open-ExternalLink ([string]$sender.DataContext))
    })

    $fenster.Add_SourceInitialized({
        param($sender, $eventArgs)
        try {
            $handle = (New-Object System.Windows.Interop.WindowInteropHelper($sender)).Handle
            if ($handle -ne [IntPtr]::Zero) {
                $dunkel = [int][bool]$script:CurrentTheme.IsDark
                [void][PortCheck.Dwm]::DwmSetWindowAttribute($handle, 20, [ref]$dunkel, 4)
                $rund = 2
                [void][PortCheck.Dwm]::DwmSetWindowAttribute($handle, 33, [ref]$rund, 4)
            }
        } catch { }
    })

    # Merken, dass der Dialog offen ist - das Sicherheitsnetz am Hauptfenster
    # braucht diese Information, um ihn wieder nach vorn holen zu können.
    $script:WelcomeFenster = $fenster
    $script:WelcomeOffen   = $true
    $fenster.Add_Closed({
        $script:WelcomeOffen   = $false
        $script:WelcomeFenster = $null
    })

    # Entwicklerlauf: kurz zeichnen lassen, abbilden, schließen.
    if ($script:WelcomeCapture) {
        $fenster.Add_ContentRendered({
            param($sender, $eventArgs)
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(900)
            $timer.Add_Tick({
                param($t, $e)
                $t.Stop()
                try {
                    Save-WindowImage -Path $script:WelcomeCapture -Window $script:WelcomeFenster
                    Write-Output "Abbild gespeichert: $script:WelcomeCapture"
                } catch {
                    Write-Output "Abbild fehlgeschlagen: $($_.Exception.Message)"
                }
                $script:WelcomeFenster.Close()
            })
            $timer.Start()
        })
        $script:WelcomeFenster = $fenster
    }

    [void]$fenster.ShowDialog()
}

$ui.BtnShowWelcome.Add_Click({ Show-WelcomeWindow })

# ------------------------------------------------------------------------------
# Region: Ergebnis teilen
# ------------------------------------------------------------------------------

function Hide-IpAddress {
    <#
    .SYNOPSIS
        Kürzt eine IP-Adresse für die Weitergabe.
    .DESCRIPTION
        Aus 203.0.113.47 wird 203.0.xxx.xxx. Der Anbieter bleibt grob
        erkennbar, die Adresse taugt aber nicht mehr dazu, jemanden gezielt
        anzugreifen. Die Karte ist zum Teilen gedacht - da hat eine
        vollständige IP nichts verloren.
    #>
    param([string]$Address)
    if (-not $Address) { return 'unbekannt' }
    $teile = $Address -split '\.'
    if ($teile.Count -ne 4) { return 'unbekannt' }
    return "$($teile[0]).$($teile[1]).xxx.xxx"
}

function Copy-ShareCardToClipboard {
    <#
    .SYNOPSIS
        Zeichnet die Karte und legt sie als Bild in die Zwischenablage.
    #>
    param([Parameter(Mandatory = $true)]$Card)

    $Card.UpdateLayout()
    $breite = [int][Math]::Ceiling($Card.ActualWidth)
    $hoehe  = [int][Math]::Ceiling($Card.ActualHeight)
    if ($breite -le 0 -or $hoehe -le 0) { throw 'Die Karte hat noch keine Größe.' }

    # Doppelte Auflösung: in Discord und auf hochauflösenden Bildschirmen
    # sieht das Bild sonst matschig aus.
    $skala      = 2.0
    $zielBreite = [int]($breite * $skala)
    $zielHoehe  = [int]($hoehe * $skala)
    $punktdichte = 96 * $skala

    # Die Werte werden bewusst vorher ausgerechnet und dann über -ArgumentList
    # übergeben. Schreibt man die Ausdrücke direkt in die Klammer hinter
    # New-Object, packt PowerShell sie zu EINEM Array zusammen - der Aufruf
    # scheitert dann mit "System.Object[] kann nicht in System.UInt32
    # konvertiert werden", was den Grund gut versteckt.
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap -ArgumentList @(
        $zielBreite, $zielHoehe, $punktdichte, $punktdichte,
        [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Card)
    $bitmap.Freeze()

    [System.Windows.Clipboard]::SetImage($bitmap)
    return $bitmap
}

function Show-ShareWindow {
    <#
    .SYNOPSIS
        Zeigt die teilbare Ergebniskarte und legt sie in die Zwischenablage.
    #>
    [CmdletBinding()]
    param()

    if ($script:RawResults.Count -eq 0) {
        Set-Status 'Es gibt noch kein Ergebnis zum Teilen - erst einen Port-Test laufen lassen.' 'warn'
        return
    }

    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load($script:SharePath)
        $fenster = [System.Windows.Markup.XamlReader]::Load(
            (New-Object System.Xml.XmlNodeReader -ArgumentList $doc))
    } catch {
        Set-Status "Teilen-Fenster ließ sich nicht laden: $($_.Exception.Message)" 'error'
        return
    }

    Set-PortCheckTheme -Window $fenster -Theme $script:CurrentTheme
    $fenster.Owner = $script:Win

    $offen  = @($script:RawResults | Where-Object { $_.Status -eq 'Open' })
    $zu     = @($script:RawResults | Where-Object { $_.Status -eq 'Closed' })
    $gesamt = $script:RawResults.Count

    $fenster.FindName('TxtShareOpen').Text   = "$($offen.Count)"
    $fenster.FindName('TxtShareClosed').Text = "$($zu.Count)"
    $fenster.FindName('TxtShareTotal').Text  = "$gesamt"
    $fenster.FindName('TxtShareIp').Text     = Hide-IpAddress $script:PublicIP
    $fenster.FindName('TxtShareDate').Text   = (Get-Date).ToString('dd.MM.yyyy HH:mm')
    $fenster.FindName('TxtShareVersion').Text = "v$script:AppVersion"

    $natText = if ($script:LastNat) { $script:LastNat.Title } else { 'ungeprüft' }
    $fenster.FindName('TxtShareNat').Text = $natText

    $offeneListe = if ($offen.Count -gt 0) {
        ConvertTo-PortSpec -Ports @($offen | ForEach-Object { $_.Port })
    } else {
        'keiner der geprüften Ports'
    }
    $fenster.FindName('TxtShareOpenPorts').Text = $offeneListe

    $fenster.FindName('TxtShareSubtitle').Text = "Port-Ergebnis - $gesamt Port(s) geprüft"
    $fenster.FindName('TxtShareNote').Text =
        'Geprüft wird die Erreichbarkeit aus dem Internet über TCP. UDP-Ports lassen sich von außen nicht zuverlässig testen.'

    $karte = $fenster.FindName('ShareCard')

    $fenster.FindName('ShareTitleBar').Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        try { [System.Windows.Window]::GetWindow($sender).DragMove() } catch { }
    })

    $schliessen = {
        param($sender, $eventArgs)
        [System.Windows.Window]::GetWindow($sender).Close()
    }
    $fenster.FindName('BtnShareClose').Add_Click($schliessen)
    $fenster.FindName('BtnShareOk').Add_Click($schliessen)

    $fenster.FindName('BtnShareCopy').Add_Click({
        param($sender, $eventArgs)
        $f = [System.Windows.Window]::GetWindow($sender)
        try {
            [void](Copy-ShareCardToClipboard -Card $f.FindName('ShareCard'))
            $f.FindName('TxtShareStatus').Text = 'Erneut in die Zwischenablage kopiert.'
        } catch {
            $f.FindName('TxtShareStatus').Text = "Kopieren fehlgeschlagen: $($_.Exception.Message)"
        }
    })

    $fenster.FindName('BtnShareSave').Add_Click({
        param($sender, $eventArgs)
        $f = [System.Windows.Window]::GetWindow($sender)
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Filter = 'PNG-Bild (*.png)|*.png'
        $dialog.FileName = 'portchecker_{0:yyyy-MM-dd_HHmm}.png' -f (Get-Date)
        if ($dialog.ShowDialog() -ne $true) { return }
        try {
            $bild = Copy-ShareCardToClipboard -Card $f.FindName('ShareCard')
            $kodierer = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $kodierer.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bild))
            $strom = [System.IO.File]::Create($dialog.FileName)
            try { $kodierer.Save($strom) } finally { $strom.Dispose() }
            $f.FindName('TxtShareStatus').Text = "Gespeichert: $($dialog.FileName)"
        } catch {
            $f.FindName('TxtShareStatus').Text = "Speichern fehlgeschlagen: $($_.Exception.Message)"
        }
    })

    # Sobald das Fenster gezeichnet ist, die Karte automatisch kopieren.
    $script:ShareFenster = $fenster
    $fenster.Add_ContentRendered({
        param($sender, $eventArgs)
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(350)
        $timer.Add_Tick({
            param($t, $e)
            $t.Stop()
            try {
                [void](Copy-ShareCardToClipboard -Card $script:ShareFenster.FindName('ShareCard'))
                $script:ShareFenster.FindName('TxtShareStatus').Text = 'In die Zwischenablage kopiert - mit Strg+V einfügen.'
            } catch {
                $script:ShareFenster.FindName('TxtShareStatus').Text = "Automatisches Kopieren fehlgeschlagen: $($_.Exception.Message)"
            }
            if ($script:ShareCapture) {
                try {
                    Save-WindowImage -Path $script:ShareCapture -Window $script:ShareFenster
                } catch { }
                $script:ShareFenster.Close()
            }
        })
        $timer.Start()
    })

    [void]$fenster.ShowDialog()
    Set-Status 'Ergebniskarte erstellt und in die Zwischenablage gelegt.' 'ok'
}

$ui.BtnShareResult.Add_Click({ Show-ShareWindow })

# ------------------------------------------------------------------------------
# Region: Start
# ------------------------------------------------------------------------------

$script:Win.Add_SourceInitialized({
    # Erst jetzt existiert das Fensterhandle, das die DWM-Aufrufe brauchen.
    Set-WindowDarkMode -Dark $script:CurrentTheme.IsDark
})

function Set-DemoData {
    <#
    .SYNOPSIS
        Füllt die Oberfläche mit Beispieldaten - nur für die README-Bilder.
    .DESCRIPTION
        Geht bewusst NICHT ins Netz. Die IP stammt aus 203.0.113.0/24, dem in
        RFC 5737 für Dokumentation reservierten Bereich; sie gehört niemandem.
        So zeigen die Bilder jeden Zustand der Oberfläche, ohne die echte
        Adresse eines Menschen zu veröffentlichen.
    #>
    Show-PublicIp '203.0.113.47'

    Show-Network ([pscustomobject]@{
        HostName   = 'GAMING-PC'
        Gateway    = '192.168.1.1'
        LocalIPs   = @('192.168.1.42')
        DnsServers = @('192.168.1.1', '9.9.9.9')
        Adapters   = @(
            [pscustomobject]@{ Name = 'Ethernet'; Description = 'Realtek PCIe 2.5GbE Family Controller'
                               Type = 'Ethernet'; SpeedMbps = 2500; MacAddress = 'A4:B1:C2:D3:E4:F5'
                               IPv4 = '192.168.1.42' }
            [pscustomobject]@{ Name = 'WLAN'; Description = 'Intel Wi-Fi 6E AX211 160MHz'
                               Type = 'Wireless80211'; SpeedMbps = 1200; MacAddress = 'B8:9A:2E:11:07:C3'
                               IPv4 = '192.168.1.77' }
        )
    })

    foreach ($sample in @(
        [pscustomobject]@{ Port=80;    Status='Open';    Provider='yougetsignal.com'; Note=''; DurationMs=1180 }
        [pscustomobject]@{ Port=443;   Status='Open';    Provider='yougetsignal.com'; Note=''; DurationMs=1094 }
        [pscustomobject]@{ Port=3074;  Status='Closed';  Provider='yougetsignal.com'; Note=''; DurationMs=1247 }
        [pscustomobject]@{ Port=3075;  Status='Closed';  Provider='yougetsignal.com'; Note=''; DurationMs=1203 }
        [pscustomobject]@{ Port=25565; Status='Open';    Provider='yougetsignal.com'
                           Note='Port lokal belegt - läuft dort schon ein Dienst?'; DurationMs=1332 }
        [pscustomobject]@{ Port=27015; Status='Closed';  Provider='yougetsignal.com'; Note=''; DurationMs=1156 }
        [pscustomobject]@{ Port=27016; Status='Unknown'; Provider='yougetsignal.com'
                           Note='Antwort des Dienstes unklar - vermutlich Rate-Limit.'; DurationMs=2011 }
        [pscustomobject]@{ Port=27036; Status='Closed';  Provider='canyouseeme.org'; Note=''; DurationMs=1420 })) {
        $script:RawResults.Add($sample)
    }
    Update-ResultView
    Update-ResultCounters
    $ui.ProgPorts.Value      = 100
    $ui.TxtPortSpec.Text     = '80,443,3074,3075,25565,27015,27016,27036'
    $ui.TxtPortProgress.Text = 'Fertig: 8 Port(s) geprüft in 00:00:19 - 3 offen.'

    Show-NatResult ([pscustomobject]@{
        Level      = 'Moderate'
        Behaviour  = 'Endpoint-Independent Mapping (Cone-NAT)'
        Title      = 'MODERAT'
        ExternalIP = '203.0.113.47'
        LocalIP    = '192.168.1.42'
        IsCgnat    = $false
        Mappings   = @(
            [pscustomobject]@{ Server='stun.l.google.com';   ExtIP='203.0.113.47'; ExtPort=54321 }
            [pscustomobject]@{ Server='stun1.l.google.com';  ExtIP='203.0.113.47'; ExtPort=54321 }
            [pscustomobject]@{ Server='stun.cloudflare.com'; ExtIP='203.0.113.47'; ExtPort=54321 }
            [pscustomobject]@{ Server='stun.nextcloud.com';  ExtIP='203.0.113.47'; ExtPort=54321 }
        )
        Reasons = @(
            'Dein Router benutzt für alle Ziele dieselbe öffentliche Adresse und denselben Port.',
            'Das ist gutmütiges NAT - mit Portweiterleitung oder UPnP wird daraus im Spiel "OFFEN".',
            'Prüfe im Reiter Port-Test, ob deine Spiele-Ports wirklich erreichbar sind: offen = NAT offen, geschlossen = NAT moderat.'
        )
    })

    Show-Upnp @(
        [pscustomobject]@{ Address='192.168.1.1'; Server='FRITZ!Box 7590 UPnP/1.0 AVM FRITZ!Box'
                           Location='http://192.168.1.1:49000/igddesc.xml' })

    # UPnP-Verwaltung mit einer harmlosen und einer riskanten Freigabe -
    # letztere zeigt, wie das Werkzeug davor warnt.
    $ui.UpnpManageCard.Visibility = 'Visible'
    $ui.TxtUpnpRouterInfo.Text = 'Router: FRITZ!Box 7590  (192.168.1.1)   -   nach außen: 203.0.113.47'
    $ui.TxtUpnpState.Text = 'UPnP verfügbar - Freigaben lassen sich hier direkt verwalten.'
    Show-UpnpMappings @(
        [pscustomobject]@{ ExternalPort=25565; InternalPort=25565; Protocol='TCP'
                           Client='192.168.1.42'; Description='Minecraft-Server'; Enabled=$true; LeaseSeconds=0 }
        [pscustomobject]@{ ExternalPort=3389;  InternalPort=3389;  Protocol='TCP'
                           Client='192.168.1.42'; Description='Remote'; Enabled=$true; LeaseSeconds=0 }
        [pscustomobject]@{ ExternalPort=7777;  InternalPort=7777;  Protocol='UDP'
                           Client='192.168.1.55'; Description='Valheim'; Enabled=$true; LeaseSeconds=0 }
    )

    # Sicherheits-Check
    Show-SecurityResult (Get-SecurityAssessment -Results @(
        [pscustomobject]@{ Port=3389;  Status='Open' }
        [pscustomobject]@{ Port=445;   Status='Closed' }
        [pscustomobject]@{ Port=22;    Status='Open' }
        [pscustomobject]@{ Port=23;    Status='Closed' }
        [pscustomobject]@{ Port=3306;  Status='Open' }
        [pscustomobject]@{ Port=5900;  Status='Closed' }
    ))
    $ui.ProgSecurity.Value = 100
    $ui.TxtSecurityProgress.Text = 'Fertig. 20 Risiko-Ports geprüft.'

    # IPv6
    Show-Ipv6Result ([pscustomobject]@{
        HasGlobalAddress = $true
        LocalAddresses   = @('2001:db8:85a3::8a2e:370:7334')
        InternetWorks    = $true
        PublicAddress    = '2001:db8:85a3::8a2e:370:7334'
        Level            = 'Full'
        Title            = 'IPv6 vorhanden'
        Reasons          = @(
            'Dein Anschluss ist über IPv6 im Internet unterwegs.',
            'Über IPv6 hat jedes Gerät eine eigene, weltweit gültige Adresse - eine Portweiterleitung wie bei IPv4 gibt es hier gar nicht.',
            'Wenn dein IPv4 an CGNAT hängt, ist das dein Ausweg: Mitspieler und Server, die IPv6 können, erreichen dich direkt.'
        )
    })

    # Verbindungsqualität
    foreach ($zeile in @(
        @{ L='Dein Router';    H='192.168.1.1'; P='3 ms';  D='min 2 / max 5 / Jitter 0.8 / Verlust 0 %';   R='Sehr gut - niedrig und gleichmässig.'; T='Ok'
           M='Nur dein Heimnetz. Schwankt es schon hier, liegt es an WLAN, Kabel oder Router.' },
        @{ L='Dein DNS-Server';H='192.168.1.1'; P='4 ms';  D='min 3 / max 7 / Jitter 1.1 / Verlust 0 %';   R='Sehr gut - niedrig und gleichmässig.'; T='Ok'
           M='Meist der erste Rechner beim Anbieter. Zeigt die Qualität deiner Anschlussleitung.' },
        @{ L='Cloudflare';     H='1.1.1.1';     P='14 ms'; D='min 13 / max 18 / Jitter 1.4 / Verlust 0 %'; R='Sehr gut - niedrig und gleichmässig.'; T='Ok'
           M='Nächstgelegener Knotenpunkt eines weltweiten Netzes. Der Richtwert für deine Verbindung.' },
        @{ L='Google';         H='8.8.8.8';     P='19 ms'; D='min 17 / max 26 / Jitter 2.1 / Verlust 0 %'; R='Sehr gut - niedrig und gleichmässig.'; T='Ok'
           M='Zweiter Richtwert. Weicht er stark ab, hakt es an der Wegführung deines Anbieters.' },
        @{ L='Quad9 (Europa)'; H='9.9.9.9';     P='23 ms'; D='min 21 / max 31 / Jitter 2.6 / Verlust 0 %'; R='Sehr gut - niedrig und gleichmässig.'; T='Ok'
           M='Dritter Vergleichswert für europäische Ziele.' })) {
        $script:QualityRows.Add([pscustomobject]@{
            Label = $zeile.L; HostText = $zeile.H; Meaning = $zeile.M
            PingText = $zeile.P; DetailText = $zeile.D; RatingText = $zeile.R
            Accent = (Get-ThemeBrush $zeile.T)
        })
    }
    $ui.ItemsQuality.ItemsSource = $script:QualityRows.ToArray()
    $ui.TxtQualityProgress.Text = 'Messung abgeschlossen.'

    Set-Status 'Beispieldaten - dieses Fenster dient nur den Bildern in der README.' 'ok'
}

$script:Win.Add_Loaded({
    $script:Pump.Start()

    if ($DemoMode) {
        # Keine Netzzugriffe, keine echten Daten.
        Set-DemoData
        if ($script:ShareCapture) { Show-ShareWindow; $script:Win.Close() }
        return
    }

    if ($script:Settings.LastPorts) { $ui.TxtPortSpec.Text = [string]$script:Settings.LastPorts }
    [void](Start-Work -Body $script:WorkerInit)
    Set-Status 'Ermittle Netzwerkdaten...' 'busy'
})

# Das Willkommensfenster darf ERST aufgehen, wenn das Hauptfenster wirklich auf
# dem Bildschirm steht.
#
# Warum das wichtig ist: Loaded feuert, bevor das Fenster gezeichnet ist. Ein
# modaler Dialog an dieser Stelle blockiert den Ablauf, das Hauptfenster wird
# nie sichtbar - es hat dann zwar einen Eintrag in der Taskleiste, aber nichts
# zum Anzeigen. Nimmt jetzt ein anderes Programm den Fokus, klickt man in der
# Taskleiste auf ein unsichtbares Fenster, und das einzig sichtbare hat keinen
# Eintrag. Die Anwendung ist damit praktisch verloren. Genau so ist es in
# Version 1.0.0 passiert.
#
# ContentRendered feuert nach dem ersten Zeichnen. Der kurze Timer danach gibt
# Windows noch Zeit, das Fenster wirklich einzublenden, bevor der modale Dialog
# übernimmt.
#
# Bewusst ein DispatcherTimer und NICHT Dispatcher.BeginInvoke mit [action]{...}:
# ein so als Delegat übergebener PowerShell-Scriptblock wurde hier gar nicht
# ausgeführt, der Dialog erschien dann überhaupt nicht mehr. Der Timer ist im
# Projekt mehrfach erprobt.
$script:Win.Add_ContentRendered({
    if (-not $script:ZeigeWillkommen) { return }
    $script:ZeigeWillkommen = $false      # nur ein einziges Mal

    $anlauf = New-Object System.Windows.Threading.DispatcherTimer
    $anlauf.Interval = [TimeSpan]::FromMilliseconds(300)
    $anlauf.Add_Tick({
        param($sender, $eventArgs)
        $sender.Stop()
        Show-WelcomeWindow
        $script:Settings.WelcomeShown = $true
        Export-AppSettings
    })
    $anlauf.Start()
})

# Sicherheitsnetz: Wird das Hauptfenster aktiviert (etwa über die Taskleiste),
# waehrend der modale Dialog offen ist, holen wir den Dialog nach vorn. Ohne das
# passiert beim Klick scheinbar gar nichts, weil das Hauptfenster blockiert ist.
$script:Win.Add_Activated({
    if ($script:WelcomeOffen -and $script:WelcomeFenster) {
        try { [void]$script:WelcomeFenster.Activate() } catch { }
    }
})

$script:Win.Add_Closing({
    # Laufende Arbeit sauber beenden, sonst bleibt PowerShell im Speicher hängen.
    $script:Sync.Cancel = $true
    $script:Pump.Stop()
    if ($script:Job) {
        try { $script:Job.Shell.Stop() } catch { }
        try { $script:Job.Shell.Dispose() } catch { }
        try { $script:Job.Runspace.Close(); $script:Job.Runspace.Dispose() } catch { }
        $script:Job = $null
    }
    Export-AppSettings
})

Switch-AppTheme $script:CurrentTheme
Show-Page $(if ($StartPage) { $StartPage } else { 'NavDashboard' })
Update-ResultView

# Entwickler-Optionen in den Skript-Bereich heben, damit Ereignis-Handler
# sie sehen (Parameter sind dort nicht zuverlässig sichtbar).
$script:CaptureDelay = $CaptureDelayMs
$script:LiveSpec     = $LiveTest
$script:LiveCapture  = $(if ($LiveTest -and $CaptureTo) { $CaptureTo } else { '' })
$script:LiveReport   = New-Object 'System.Collections.Generic.List[string]'

# Willkommensfenster: beim ersten Start automatisch, sonst nur auf Wunsch.
# Bei Selbsttest und Bildaufnahme bleibt es aus, damit nichts blockiert.
$script:WelcomeCapture  = $(if ($ShowWelcome -and $CaptureTo) { $CaptureTo } else { '' })
$script:ShareCapture    = $(if ($ShowShare -and $CaptureTo) { $CaptureTo } else { '' })
$script:ShareFenster    = $null
$script:WelcomeFenster  = $null
$script:WelcomeOffen    = $false
$script:ZeigeWillkommen = [bool](
    ($ShowWelcome -or -not $script:Settings.WelcomeShown) -and
    -not $SelfTest -and -not $LiveTest -and
    (-not $CaptureTo -or $script:WelcomeCapture))

# ------------------------------------------------------------------------------
# Region: Entwickler-Optionen
# ------------------------------------------------------------------------------

function Save-WindowImage {
    <#
    .SYNOPSIS
        Legt ein PNG des Fensterinhalts ab.
    .DESCRIPTION
        Zeichnet den Elementbaum direkt (RenderTargetBitmap). Das ist deutlich
        verlässlicher als ein Bildschirmfoto: es ist egal, ob das Fenster
        gerade verdeckt ist oder den Fokus hat.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [System.Windows.Window]$Window
    )

    if (-not $Window) { $Window = $script:Win }

    # Erst das Layout nachziehen lassen. Ohne das zeichnet RenderTargetBitmap
    # den Stand VOR den letzten Änderungen - Listen erscheinen dann leer und
    # Texte sind veraltet.
    $Window.UpdateLayout()

    $width  = [int]$Window.ActualWidth
    $height = [int]$Window.ActualHeight
    if ($width -le 0 -or $height -le 0) { throw 'Fenster hat noch keine Größe.' }

    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
        $width, $height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Window)

    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $stream = [System.IO.File]::Create($Path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

# Abbild NUR vom Willkommensfenster: das Hauptfenster bleibt zu.
# Muss NACH Save-WindowImage stehen - PowerShell kennt eine Funktion erst ab
# der Zeile, in der sie definiert wurde.
if ($script:WelcomeCapture) {
    Show-WelcomeWindow
    exit 0
}

if ($SelfTest) {
    # Baut alles auf, schaltet jede Seite und jede Farbwelt einmal durch und
    # meldet das Ergebnis als Text + Rückgabewert. Kein Fenster, kein Netz.
    $problems = New-Object 'System.Collections.Generic.List[string]'

    foreach ($navName in @('NavDashboard','NavPorts','NavPresets','NavNat','NavHowTo','NavSecurity','NavQuality','NavNetwork','NavSettings','NavAbout')) {
        try {
            Show-Page $navName
            if ($ui[$script:Pages[$navName]].Visibility -ne 'Visible') {
                $problems.Add("Seite $navName wurde nicht sichtbar.")
            }
        } catch { $problems.Add("Seite ${navName}: $($_.Exception.Message)") }
    }

    foreach ($candidate in $script:Themes) {
        try { Switch-AppTheme $candidate }
        catch { $problems.Add("Farbwelt $($candidate.Id): $($_.Exception.Message)") }
    }

    # Ergebniszeilen mit allen vier Statuswerten erzeugen
    foreach ($state in @('Open', 'Closed', 'Unknown', 'Error')) {
        try {
            $row = New-ResultRow ([pscustomobject]@{
                Port = 1; Status = $state; Provider = 'test'; Note = ''; DurationMs = 1 })
            if (-not $row.StatusFg) { $problems.Add("Statusfarbe fehlt für $state.") }
        } catch { $problems.Add("Ergebniszeile ${state}: $($_.Exception.Message)") }
    }

    if ($problems.Count -eq 0) {
        Write-Output "SELFTEST OK - $($script:Themes.Count) Farbwelten, $($script:Pages.Count) Seiten, $($script:PresetViews.Count) Presets"
        exit 0
    }
    foreach ($problem in $problems) { Write-Output "SELFTEST FEHLER: $problem" }
    exit 1
}

if ($CaptureTo -and -not $LiveTest -and -not $script:ShareCapture) {
    # ACHTUNG: hier bewusst KEIN .GetNewClosure(). Eine so erzeugte Closure
    # bekommt ein eigenes Modul - und darin zeigt $script: auf dessen eigene
    # Ebene, nicht mehr auf dieses Skript. $script:Win wäre dann leer.
    # Deshalb: normaler Scriptblock, und den Timer über $sender ansprechen.
    $script:CapturePath = $CaptureTo
    $script:Win.Add_ContentRendered({
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds($script:CaptureDelay)
        $timer.Add_Tick({
            param($sender, $eventArgs)
            $sender.Stop()
            try {
                Save-WindowImage -Path $script:CapturePath
                Write-Output "Abbild gespeichert: $script:CapturePath"
            } catch {
                Write-Output "Abbild fehlgeschlagen: $($_.Exception.Message)"
            }
            $script:Win.Close()
        })
        $timer.Start()
    })
}

[void]$script:Win.ShowDialog()

# Erst hier ist der Skript-Fluss wieder normal - Ausgaben aus Ereignis-Handlern
# waeren vorher verlorengegangen.
if ($script:LiveReport.Count -gt 0) {
    Write-Output ''
    Write-Output '  LIVETEST - Ergebnis des kompletten Wegs Runspace -> Warteschlange -> Anzeige'
    Write-Output '  ---------------------------------------------------------------------------'
    foreach ($zeile in $script:LiveReport) { Write-Output ('  ' + $zeile) }
    Write-Output ''
}
