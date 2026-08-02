#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - Testsuite
================================================================================
 Eigener kleiner Testläufer, bewusst ohne Pester oder sonstige Fremdmodule:
 wer das Projekt klont, soll die Tests sofort ausführen können, ohne vorher
 irgendetwas zu installieren.

 Aufruf:   .\tests\Run-Tests.ps1
 Rückgabe: 0 = alles grün, 1 = mindestens ein Test rot

 Kein Test hier geht ins Internet. Netzabhängige Funktionen werden mit
 künstlichen Daten geprüft - so laufen die Tests auch offline und in der
 GitHub-Action zuverlässig durch.

 Lizenz: MIT (siehe LICENSE)
================================================================================
#>

param(
    # Überspringt den Aufbau des Fensters (für Umgebungen ganz ohne Desktop)
    [switch]$SkipGui
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Root    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:SrcDir  = Join-Path $script:Root 'src'
$script:Bestanden = 0
$script:Gescheitert = 0
$script:Gruppe = ''

# ------------------------------------------------------------------------------
# Region: Mini-Testgerüst
# ------------------------------------------------------------------------------

function Start-Group {
    param([string]$Name)
    $script:Gruppe = $Name
    Write-Host ''
    Write-Host "  $Name" -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 68)) -ForegroundColor DarkGray
}

function Test-Case {
    <#
    .SYNOPSIS
        Führt einen Testfall aus. Der Block muss $true liefern.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )
    try {
        $ergebnis = & $Body
        if ($ergebnis -eq $true) {
            $script:Bestanden++
            Write-Host ('    [ok]   ' + $Name) -ForegroundColor Green
        } else {
            $script:Gescheitert++
            Write-Host ('    [FEHL] ' + $Name) -ForegroundColor Red
            Write-Host ('           erwartet: True, bekommen: ' + ($ergebnis | Out-String).Trim()) -ForegroundColor DarkRed
        }
    } catch {
        $script:Gescheitert++
        Write-Host ('    [FEHL] ' + $Name) -ForegroundColor Red
        Write-Host ('           Ausnahme: ' + $_.Exception.Message) -ForegroundColor DarkRed
    }
}

function Assert-Equal {
    param($Erwartet, $Bekommen)
    if ($Erwartet -is [array] -or $Bekommen -is [array]) {
        $a = @($Erwartet) -join ','
        $b = @($Bekommen) -join ','
        if ($a -eq $b) { return $true }
        return "erwartet [$a], bekommen [$b]"
    }
    if ($Erwartet -eq $Bekommen) { return $true }
    return "erwartet [$Erwartet], bekommen [$Bekommen]"
}

# ------------------------------------------------------------------------------
# Region: Laden
# ------------------------------------------------------------------------------

Write-Host ''
Write-Host '  ====================================================================' -ForegroundColor DarkCyan
Write-Host '   TEE PortChecker - Testsuite' -ForegroundColor Cyan
Write-Host '  ====================================================================' -ForegroundColor DarkCyan

. (Join-Path $script:SrcDir 'PortCheck.Core.ps1')
. (Join-Path $script:SrcDir 'PortCheck.Presets.ps1')

$script:GuiVerfuegbar = $false
if (-not $SkipGui) {
    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
        . (Join-Path $script:SrcDir 'PortCheck.Themes.ps1')
        $script:GuiVerfuegbar = $true
    } catch {
        Write-Host "  WPF nicht verfügbar, Oberflächen-Tests entfallen: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------------------
Start-Group 'Port-Eingaben zerlegen (ConvertFrom-PortSpec)'
# ------------------------------------------------------------------------------

Test-Case 'Einzelner Port' {
    Assert-Equal @(80) (ConvertFrom-PortSpec -Spec '80').Ports
}
Test-Case 'Liste mit Komma' {
    Assert-Equal @(80, 443, 3074) (ConvertFrom-PortSpec -Spec '80,443,3074').Ports
}
Test-Case 'Liste mit Leerzeichen und Semikolon' {
    Assert-Equal @(80, 443, 3074) (ConvertFrom-PortSpec -Spec '80; 443  3074').Ports
}
Test-Case 'Bereich' {
    Assert-Equal @(20, 21, 22, 23) (ConvertFrom-PortSpec -Spec '20-23').Ports
}
Test-Case 'Bereich rückwärts wird gedreht' {
    Assert-Equal @(20, 21, 22) (ConvertFrom-PortSpec -Spec '22-20').Ports
}
Test-Case 'Gemischt, sortiert und ohne Doppelte' {
    Assert-Equal @(80, 443, 444, 445) (ConvertFrom-PortSpec -Spec '443-445,80,443').Ports
}
Test-Case 'Leere Eingabe ergibt leere Liste' {
    (ConvertFrom-PortSpec -Spec '').Ports.Count -eq 0
}
Test-Case 'Nur Leerzeichen ergibt leere Liste' {
    (ConvertFrom-PortSpec -Spec '   ').Ports.Count -eq 0
}
Test-Case 'Buchstaben landen in Invalid' {
    $r = ConvertFrom-PortSpec -Spec '80,abc,443'
    (Assert-Equal @(80, 443) $r.Ports) -eq $true -and (Assert-Equal @('abc') $r.Invalid) -eq $true
}
Test-Case 'Port 0 ist ungültig' {
    $r = ConvertFrom-PortSpec -Spec '0'
    $r.Ports.Count -eq 0 -and $r.Invalid.Count -eq 1
}
Test-Case 'Port 65536 ist ungültig' {
    $r = ConvertFrom-PortSpec -Spec '65536'
    $r.Ports.Count -eq 0 -and $r.Invalid.Count -eq 1
}
Test-Case 'Port 65535 ist gültig' {
    Assert-Equal @(65535) (ConvertFrom-PortSpec -Spec '65535').Ports
}
Test-Case 'Bereich über die Obergrenze hinaus wird abgelehnt' {
    $r = ConvertFrom-PortSpec -Spec '65530-70000'
    $r.Ports.Count -eq 0 -and $r.Invalid.Count -eq 1
}
Test-Case 'Grosser Bereich hat die richtige Anzahl' {
    (ConvertFrom-PortSpec -Spec '1-1024').Ports.Count -eq 1024
}

# ------------------------------------------------------------------------------
Start-Group 'Portliste zusammenfassen (ConvertTo-PortSpec)'
# ------------------------------------------------------------------------------

Test-Case 'Zusammenhängende Ports werden zum Bereich' {
    Assert-Equal '80, 443-445' (ConvertTo-PortSpec -Ports @(80, 443, 444, 445))
}
Test-Case 'Einzelne Ports bleiben einzeln' {
    Assert-Equal '80, 443, 8080' (ConvertTo-PortSpec -Ports @(80, 443, 8080))
}
Test-Case 'Unsortierte Eingabe wird sortiert' {
    Assert-Equal '80, 443-445' (ConvertTo-PortSpec -Ports @(445, 80, 444, 443))
}
Test-Case 'Doppelte werden entfernt' {
    Assert-Equal '80, 443' (ConvertTo-PortSpec -Ports @(80, 443, 80))
}
Test-Case 'Leere Liste ergibt leeren Text' {
    Assert-Equal '' (ConvertTo-PortSpec -Ports @())
}
Test-Case 'Hin und zurück ergibt dasselbe' {
    $original = @(1, 2, 3, 80, 443, 27015, 27016, 27017)
    Assert-Equal $original (ConvertFrom-PortSpec -Spec (ConvertTo-PortSpec -Ports $original)).Ports
}

# ------------------------------------------------------------------------------
Start-Group 'Private und CGNAT-Adressen (Test-PrivateIPv4)'
# ------------------------------------------------------------------------------

Test-Case '10.0.0.1 ist privat'          { (Test-PrivateIPv4 '10.0.0.1') -eq $true }
Test-Case '192.168.1.1 ist privat'       { (Test-PrivateIPv4 '192.168.1.1') -eq $true }
Test-Case '172.16.0.1 ist privat'        { (Test-PrivateIPv4 '172.16.0.1') -eq $true }
Test-Case '172.31.255.254 ist privat'    { (Test-PrivateIPv4 '172.31.255.254') -eq $true }
Test-Case '172.15.0.1 ist NICHT privat'  { (Test-PrivateIPv4 '172.15.0.1') -eq $false }
Test-Case '172.32.0.1 ist NICHT privat'  { (Test-PrivateIPv4 '172.32.0.1') -eq $false }
Test-Case '100.64.0.1 ist CGNAT'         { (Test-PrivateIPv4 '100.64.0.1') -eq $true }
Test-Case '100.127.255.1 ist CGNAT'      { (Test-PrivateIPv4 '100.127.255.1') -eq $true }
Test-Case '100.63.0.1 ist NICHT CGNAT'   { (Test-PrivateIPv4 '100.63.0.1') -eq $false }
Test-Case '100.128.0.1 ist NICHT CGNAT'  { (Test-PrivateIPv4 '100.128.0.1') -eq $false }
Test-Case '127.0.0.1 ist Loopback'       { (Test-PrivateIPv4 '127.0.0.1') -eq $true }
Test-Case '169.254.1.1 ist APIPA'        { (Test-PrivateIPv4 '169.254.1.1') -eq $true }
Test-Case '8.8.8.8 ist öffentlich'       { (Test-PrivateIPv4 '8.8.8.8') -eq $false }
Test-Case '203.0.113.47 ist öffentlich'  { (Test-PrivateIPv4 '203.0.113.47') -eq $false }
Test-Case 'Leere Eingabe ist nicht privat' { (Test-PrivateIPv4 '') -eq $false }
Test-Case 'Unsinn ist nicht privat'      { (Test-PrivateIPv4 'keine-ip') -eq $false }

# ------------------------------------------------------------------------------
Start-Group 'STUN-Antworten zerlegen (ConvertFrom-StunResponse)'
# ------------------------------------------------------------------------------

function New-StunResponse {
    <#
    .SYNOPSIS
        Baut ein echtes STUN-Binding-Response-Paket für die Tests.
    .DESCRIPTION
        Damit lässt sich der Parser vollständig prüfen, ohne einen STUN-Server
        im Internet zu befragen.
    #>
    param(
        [byte[]]$TxId,
        [string]$IP = '203.0.113.47',
        [int]$Port = 54321,
        [switch]$UseMappedAddress,   # altes MAPPED-ADDRESS statt XOR-Variante
        [byte]$Cookie0 = 0x21
    )

    $oktette = $IP -split '\.' | ForEach-Object { [byte]$_ }
    $paket = New-Object 'System.Collections.Generic.List[byte]'

    # Kopf
    $paket.Add(0x01); $paket.Add(0x01)              # Binding Response
    $paket.Add(0x00); $paket.Add(0x0C)              # Länge der Nutzdaten
    $paket.Add($Cookie0); $paket.Add(0x12); $paket.Add(0xA4); $paket.Add(0x42)
    foreach ($b in $TxId) { $paket.Add($b) }

    if ($UseMappedAddress) {
        $paket.Add(0x00); $paket.Add(0x01)          # MAPPED-ADDRESS
        $paket.Add(0x00); $paket.Add(0x08)
        $paket.Add(0x00); $paket.Add(0x01)          # reserviert, Familie IPv4
        $paket.Add([byte](($Port -shr 8) -band 0xFF))
        $paket.Add([byte]($Port -band 0xFF))
        foreach ($o in $oktette) { $paket.Add($o) }
    } else {
        $paket.Add(0x00); $paket.Add(0x20)          # XOR-MAPPED-ADDRESS
        $paket.Add(0x00); $paket.Add(0x08)
        $paket.Add(0x00); $paket.Add(0x01)
        $xorPort = $Port -bxor 0x2112
        $paket.Add([byte](($xorPort -shr 8) -band 0xFF))
        $paket.Add([byte]($xorPort -band 0xFF))
        $magic = @(0x21, 0x12, 0xA4, 0x42)
        for ($i = 0; $i -lt 4; $i++) { $paket.Add([byte]($oktette[$i] -bxor $magic[$i])) }
    }
    return $paket.ToArray()
}

$txId = [byte[]](1..12)

Test-Case 'XOR-MAPPED-ADDRESS wird korrekt gelesen' {
    $antwort = ConvertFrom-StunResponse -Response (New-StunResponse -TxId $txId) -TransactionId $txId
    $antwort.IP -eq '203.0.113.47' -and $antwort.Port -eq 54321
}
Test-Case 'Altes MAPPED-ADDRESS wird ebenfalls gelesen' {
    $antwort = ConvertFrom-StunResponse -Response (New-StunResponse -TxId $txId -UseMappedAddress) -TransactionId $txId
    $antwort.IP -eq '203.0.113.47' -and $antwort.Port -eq 54321
}
Test-Case 'Fremde Transaction-ID wird abgewiesen' {
    $andere = [byte[]](21..32)
    $null -eq (ConvertFrom-StunResponse -Response (New-StunResponse -TxId $txId) -TransactionId $andere)
}
Test-Case 'Falscher Magic Cookie wird abgewiesen' {
    $null -eq (ConvertFrom-StunResponse -Response (New-StunResponse -TxId $txId -Cookie0 0x99) -TransactionId $txId)
}
Test-Case 'Zu kurzes Paket wird abgewiesen' {
    $null -eq (ConvertFrom-StunResponse -Response ([byte[]](1..10)) -TransactionId $txId)
}
Test-Case 'Leeres Paket wird abgewiesen' {
    $null -eq (ConvertFrom-StunResponse -Response @() -TransactionId $txId)
}
Test-Case 'Anfrage statt Antwort wird abgewiesen' {
    $paket = New-StunResponse -TxId $txId
    $paket[0] = 0x00; $paket[1] = 0x01          # Binding Request
    $null -eq (ConvertFrom-StunResponse -Response $paket -TransactionId $txId)
}
Test-Case 'Abgeschnittenes Attribut sprengt den Parser nicht' {
    $paket = New-StunResponse -TxId $txId
    $kurz  = $paket[0..($paket.Length - 4)]
    $null -eq (ConvertFrom-StunResponse -Response $kurz -TransactionId $txId)
}
Test-Case 'Port 1 und 65535 überstehen die XOR-Rechnung' {
    $a = ConvertFrom-StunResponse -Response (New-StunResponse -TxId $txId -Port 1) -TransactionId $txId
    $b = ConvertFrom-StunResponse -Response (New-StunResponse -TxId $txId -Port 65535) -TransactionId $txId
    $a.Port -eq 1 -and $b.Port -eq 65535
}
Test-Case 'Adresse 255.255.255.255 wird korrekt entxort' {
    $a = ConvertFrom-StunResponse -Response (New-StunResponse -TxId $txId -IP '255.255.255.255') -TransactionId $txId
    $a.IP -eq '255.255.255.255'
}

# ------------------------------------------------------------------------------
Start-Group 'NAT-Bewertung (Get-NatAssessment)'
# ------------------------------------------------------------------------------

function New-Mapping {
    param([string]$Server, [string]$IP, [int]$Port)
    [pscustomobject]@{ Server = $Server; ExtIP = $IP; ExtPort = $Port }
}

Test-Case 'Keine Antwort ergibt STRIKT' {
    (Get-NatAssessment -Mappings @() -LocalIP '192.168.1.5' -PublicIP '203.0.113.47').Level -eq 'Strict'
}
Test-Case 'Gleiche Abbildung überall ergibt MODERAT (Cone)' {
    $m = @((New-Mapping 'a' '203.0.113.47' 1234), (New-Mapping 'b' '203.0.113.47' 1234))
    (Get-NatAssessment -Mappings $m -LocalIP '192.168.1.5' -PublicIP '203.0.113.47').Level -eq 'Moderate'
}
Test-Case 'Wechselnde Ports ergeben STRIKT (symmetrisch)' {
    $m = @((New-Mapping 'a' '203.0.113.47' 1234), (New-Mapping 'b' '203.0.113.47' 5678))
    (Get-NatAssessment -Mappings $m -LocalIP '192.168.1.5' -PublicIP '203.0.113.47').Level -eq 'Strict'
}
Test-Case 'Lokale IP gleich externe IP ergibt OFFEN' {
    $m = @((New-Mapping 'a' '203.0.113.47' 1234), (New-Mapping 'b' '203.0.113.47' 1234))
    (Get-NatAssessment -Mappings $m -LocalIP '203.0.113.47' -PublicIP '203.0.113.47').Level -eq 'Open'
}
Test-Case 'CGNAT-Adresse erzwingt STRIKT trotz Cone-Verhalten' {
    $m = @((New-Mapping 'a' '100.80.1.2' 1234), (New-Mapping 'b' '100.80.1.2' 1234))
    $r = Get-NatAssessment -Mappings $m -LocalIP '192.168.1.5' -PublicIP '100.80.1.2'
    $r.Level -eq 'Strict' -and $r.IsCgnat -eq $true
}
Test-Case 'Abweichende HTTP- und STUN-Adresse wird angemerkt' {
    $m = @((New-Mapping 'a' '203.0.113.47' 1234))
    $r = Get-NatAssessment -Mappings $m -LocalIP '192.168.1.5' -PublicIP '198.51.100.9'
    (@($r.Reasons) -join ' ') -like '*VPN*'
}
Test-Case 'Bewertung liefert immer eine Begründung' {
    foreach ($fall in @(@(), @((New-Mapping 'a' '203.0.113.47' 1)), @((New-Mapping 'a' '203.0.113.47' 1), (New-Mapping 'b' '203.0.113.47' 2)))) {
        $r = Get-NatAssessment -Mappings $fall -LocalIP '192.168.1.5' -PublicIP '203.0.113.47'
        if (@($r.Reasons).Count -eq 0) { return "Fall ohne Begründung" }
        if (-not $r.Title) { return "Fall ohne Titel" }
    }
    return $true
}

# ------------------------------------------------------------------------------
Start-Group 'Preset-Datenbank'
# ------------------------------------------------------------------------------

$alle = @(Get-PortCheckPresets)

Test-Case 'Es gibt Presets' { $alle.Count -gt 50 }
Test-Case 'Alle Ids sind eindeutig' {
    $doppelt = @($alle | Group-Object Id | Where-Object { $_.Count -gt 1 })
    if ($doppelt.Count -eq 0) { return $true }
    return 'doppelt: ' + (($doppelt | ForEach-Object { $_.Name }) -join ', ')
}
Test-Case 'Alle Ports liegen zwischen 1 und 65535' {
    $schlecht = @($alle | ForEach-Object { $_.TCP + $_.UDP } | Where-Object { $_ -lt 1 -or $_ -gt 65535 })
    if ($schlecht.Count -eq 0) { return $true }
    return 'ungültig: ' + ($schlecht -join ', ')
}
Test-Case 'Jede BaseId verweist auf ein vorhandenes Preset' {
    $ids = @($alle | ForEach-Object { $_.Id })
    $tot = @($alle | Where-Object { $_.BaseId -and $ids -notcontains $_.BaseId })
    if ($tot.Count -eq 0) { return $true }
    return 'ins Leere: ' + (($tot | ForEach-Object { "$($_.Id)->$($_.BaseId)" }) -join ', ')
}
Test-Case 'Kein Preset verweist auf sich selbst' {
    @($alle | Where-Object { $_.BaseId -eq $_.Id }).Count -eq 0
}
Test-Case 'Alle Kategorien sind in der Anzeigereihenfolge bekannt' {
    $bekannt = Get-PresetCategories
    $fremd = @($alle | Where-Object { $bekannt -notcontains $_.Category } | ForEach-Object { $_.Category } | Select-Object -Unique)
    if ($fremd.Count -eq 0) { return $true }
    return 'unbekannt: ' + ($fremd -join ', ')
}
Test-Case 'Jedes Preset hat mindestens einen TCP-Port zum Prüfen' {
    $leer = @($alle | Where-Object { (Resolve-PresetPorts -Preset $_ -AllPresets $alle).TCP.Count -eq 0 })
    if ($leer.Count -eq 0) { return $true }
    return 'ohne TCP: ' + (($leer | ForEach-Object { $_.Id }) -join ', ')
}
Test-Case 'Konsolen-Preset erbt die Basisports (BO2 auf PS3)' {
    $bo2 = @($alle | Where-Object { $_.Id -eq 'bo2-ps3' })[0]
    $r = Resolve-PresetPorts -Preset $bo2 -AllPresets $alle
    # 5223 kommt von der PS3-Basis, 3074 aus dem Titel selbst
    $r.TCP -contains 5223 -and $r.TCP -contains 3074 -and $r.BaseName -like 'PlayStation 3*'
}
Test-Case 'Auflösung sortiert und entfernt Doppelte' {
    $bo2 = @($alle | Where-Object { $_.Id -eq 'bo2-ps3' })[0]
    $r = Resolve-PresetPorts -Preset $bo2 -AllPresets $alle
    $sortiert = @($r.TCP | Sort-Object -Unique)
    (Assert-Equal $sortiert $r.TCP) -eq $true
}
Test-Case 'Preset ohne BaseId hat keinen Basisnamen' {
    $pc = @($alle | Where-Object { $_.Id -eq 'bo2-pc' })[0]
    $null -eq (Resolve-PresetPorts -Preset $pc -AllPresets $alle).BaseName
}
Test-Case 'Die von dir genannten Titel sind vorhanden' {
    $pflicht = @('bo1-pc', 'bo1-ps3', 'bo1-x360', 'bo2-pc', 'bo2-ps3', 'bo2-x360', 'bo2-wiiu',
                 'bo3-pc', 'bo3-ps3', 'bo3-ps4', 'bo3-xb1', 'bo3-x360',
                 'ps3', 'ps4', 'ps5', 'xbox360', 'xboxone', 'xboxseries', 'switch', 'wiiu')
    $ids = @($alle | ForEach-Object { $_.Id })
    $fehlt = @($pflicht | Where-Object { $ids -notcontains $_ })
    if ($fehlt.Count -eq 0) { return $true }
    return 'fehlt: ' + ($fehlt -join ', ')
}
Test-Case 'Jedes Preset hat einen Namen und eine Kategorie' {
    @($alle | Where-Object { -not $_.Name -or -not $_.Category }).Count -eq 0
}

# ------------------------------------------------------------------------------
Start-Group 'Export'
# ------------------------------------------------------------------------------

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('portcheck-test-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$beispiel = @(
    [pscustomobject]@{ Port = 80;  Status = 'Open';   Provider = 'test'; Note = '';      DurationMs = 100 }
    [pscustomobject]@{ Port = 443; Status = 'Closed'; Provider = 'test'; Note = 'Hinweis'; DurationMs = 200 }
)

Test-Case 'CSV wird geschrieben und ist wieder lesbar' {
    $pfad = Join-Path $tempDir 'test.csv'
    Export-PortCheckResult -Results $beispiel -Path $pfad -Format 'csv' -PublicIP '203.0.113.47' | Out-Null
    $zurueck = @(Import-Csv $pfad)
    $zurueck.Count -eq 2 -and $zurueck[0].Port -eq '80' -and $zurueck[1].Status -eq 'Closed'
}
Test-Case 'JSON wird geschrieben und ist gültig' {
    $pfad = Join-Path $tempDir 'test.json'
    Export-PortCheckResult -Results $beispiel -Path $pfad -Format 'json' -PublicIP '203.0.113.47' | Out-Null
    $daten = Get-Content $pfad -Raw -Encoding UTF8 | ConvertFrom-Json
    $daten.Tool -eq 'TEE PortChecker' -and @($daten.Results).Count -eq 2 -and $daten.PublicIP -eq '203.0.113.47'
}
Test-Case 'Textbericht enthält die Zusammenfassung' {
    $pfad = Join-Path $tempDir 'test.txt'
    Export-PortCheckResult -Results $beispiel -Path $pfad -Format 'txt' -PublicIP '203.0.113.47' | Out-Null
    $text = Get-Content $pfad -Raw -Encoding UTF8
    $text -like '*Offen: 1*' -and $text -like '*203.0.113.47*'
}

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------------------
Start-Group 'Quelldateien'
# ------------------------------------------------------------------------------

Test-Case 'Alle Quelldateien sind UTF-8 MIT BOM' {
    # Ohne BOM liest Windows PowerShell 5.1 die Datei als ANSI und macht aus
    # jedem Umlaut zwei Zeichen Datenmüll.
    $ohne = @()
    foreach ($datei in (Get-ChildItem $script:SrcDir -File)) {
        if ($datei.Extension -ne '.ps1' -and $datei.Extension -ne '.xaml') { continue }
        $b = [System.IO.File]::ReadAllBytes($datei.FullName)
        if (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) {
            $ohne += $datei.Name
        }
    }
    if ($ohne.Count -eq 0) { return $true }
    return 'ohne BOM: ' + ($ohne -join ', ')
}
Test-Case 'Keine Quelldatei enthält noch ae/oe/ue-Ersatzschreibweise' {
    $verdaechtig = @('fuer', 'ueber', 'oeffentlich', 'pruefen', 'moeglich', 'koennen',
                     'zurueck', 'laeuft', 'naechste', 'Groesse', 'aussen', 'ausser')
    $treffer = @()
    foreach ($datei in (Get-ChildItem $script:SrcDir -File)) {
        if ($datei.Extension -ne '.ps1' -and $datei.Extension -ne '.xaml') { continue }
        $text = [System.IO.File]::ReadAllText($datei.FullName, [System.Text.Encoding]::UTF8)
        foreach ($wort in $verdaechtig) {
            if ([regex]::IsMatch($text, '\b' + $wort)) { $treffer += "$($datei.Name): $wort" }
        }
    }
    if ($treffer.Count -eq 0) { return $true }
    return ($treffer -join '; ')
}
Test-Case 'Alle Quelldateien sind syntaktisch gültiges PowerShell' {
    $fehler = @()
    foreach ($datei in (Get-ChildItem $script:SrcDir -Filter '*.ps1')) {
        $tokens = $null
        $probleme = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $datei.FullName, [ref]$tokens, [ref]$probleme)
        if ($probleme -and $probleme.Count -gt 0) {
            $fehler += "$($datei.Name): $($probleme[0].Message)"
        }
    }
    if ($fehler.Count -eq 0) { return $true }
    return ($fehler -join '; ')
}

# ------------------------------------------------------------------------------
Start-Group 'PowerShell-Eigenheiten, die uns schon getroffen haben'
# ------------------------------------------------------------------------------

Test-Case 'ToArray() auf List[object] funktioniert' {
    # Auf manchen PowerShell-5.1-Builds wirft @($listeVomTypObject) eine
    # ArgumentException. .ToArray() tut es überall - deshalb benutzt der
    # Quelltext ausschliesslich das. Dieser Test hält das fest.
    $liste = New-Object 'System.Collections.Generic.List[object]'
    $liste.Add('a'); $liste.Add('b')
    (Assert-Equal @('a', 'b') $liste.ToArray()) -eq $true
}
Test-Case 'Kein @() um eine List[object] im Quelltext' {
    $treffer = @()
    foreach ($datei in (Get-ChildItem $script:SrcDir -Filter '*.ps1')) {
        $text = [System.IO.File]::ReadAllText($datei.FullName, [System.Text.Encoding]::UTF8)
        # Namen aller Variablen finden, die als List[object] angelegt werden
        foreach ($m in [regex]::Matches($text, '\$(?:script:)?(\w+)\s*=\s*New-Object\s+.List\[object\]')) {
            $name = $m.Groups[1].Value
            if ([regex]::IsMatch($text, '@\(\$(?:script:)?' + [regex]::Escape($name) + '\)')) {
                $treffer += "$($datei.Name): `$$name"
            }
        }
    }
    if ($treffer.Count -eq 0) { return $true }
    return ($treffer -join '; ')
}

# ------------------------------------------------------------------------------
if ($script:GuiVerfuegbar) {
    Start-Group 'Farbwelten'
    # --------------------------------------------------------------------------

    $themes = @(Get-PortCheckThemes)
    $tokens = Get-PortCheckThemeTokenNames

    Test-Case 'Es gibt mehrere Farbwelten' { $themes.Count -ge 5 }
    Test-Case 'Alle Farbwelt-Ids sind eindeutig' {
        @($themes | Group-Object Id | Where-Object { $_.Count -gt 1 }).Count -eq 0
    }
    Test-Case 'Jede Farbwelt definiert alle Tokens' {
        $fehler = @()
        foreach ($t in $themes) {
            $fehlt = @($tokens | Where-Object { -not $t.Tokens.ContainsKey($_) })
            if ($fehlt.Count -gt 0) { $fehler += "$($t.Id): " + ($fehlt -join ',') }
        }
        if ($fehler.Count -eq 0) { return $true }
        return ($fehler -join '; ')
    }
    Test-Case 'Keine Farbwelt hat überflüssige Tokens' {
        $fehler = @()
        foreach ($t in $themes) {
            $zuviel = @($t.Tokens.Keys | Where-Object { $tokens -notcontains $_ })
            if ($zuviel.Count -gt 0) { $fehler += "$($t.Id): " + ($zuviel -join ',') }
        }
        if ($fehler.Count -eq 0) { return $true }
        return ($fehler -join '; ')
    }
    Test-Case 'Jeder Farbwert ist gültig' {
        $fehler = @()
        foreach ($t in $themes) {
            foreach ($k in $t.Tokens.Keys) {
                try { [void][System.Windows.Media.ColorConverter]::ConvertFromString($t.Tokens[$k]) }
                catch { $fehler += "$($t.Id).$k = $($t.Tokens[$k])" }
            }
        }
        if ($fehler.Count -eq 0) { return $true }
        return ($fehler -join '; ')
    }
    Test-Case 'Voreingestellte Farbwelt existiert und steht an erster Stelle' {
        # Get-ThemeById faellt auf Themes[0] zurueck, wenn eine gespeicherte Id
        # unbekannt ist. Waere das eine andere als die Voreinstellung, saehe ein
        # frischer Start anders aus als ein Start nach einem Fehlgriff.
        $guiQuelle = [System.IO.File]::ReadAllText(
            (Join-Path $script:SrcDir 'PortCheck.Gui.ps1'), [System.Text.Encoding]::UTF8)
        $standard = [regex]::Match($guiQuelle, "Theme\s+=\s+'([a-z]+)'").Groups[1].Value
        if (-not $standard) { return 'Voreinstellung nicht gefunden' }
        if (-not (@($themes | ForEach-Object { $_.Id }) -contains $standard)) {
            return "Voreinstellung '$standard' gibt es gar nicht"
        }
        if ($themes[0].Id -ne $standard) {
            return "Voreinstellung ist '$standard', Notnagel waere aber '$($themes[0].Id)'"
        }
        return $true
    }
    Test-Case 'Es gibt mindestens eine helle und eine dunkle Farbwelt' {
        @($themes | Where-Object { $_.IsDark }).Count -gt 0 -and
        @($themes | Where-Object { -not $_.IsDark }).Count -gt 0
    }
    Test-Case 'Statusfarben lassen sich für jede Farbwelt erzeugen' {
        foreach ($t in $themes) {
            $set = Get-StatusBrushSet -Theme $t
            foreach ($status in @('Open', 'Closed', 'Unknown', 'Error')) {
                if (-not $set[$status].Fg -or -not $set[$status].Bg) { return "$($t.Id)/$status unvollständig" }
            }
        }
        return $true
    }
    Test-Case 'Pinsel kommen ohne PSObject-Hülle zurück' {
        # Sonst lehnt WPF sie ab - siehe Hinweis in PortCheck.Themes.ps1
        $b = ConvertTo-PortCheckBrush '#FF0000'
        $b -is [System.Windows.Media.Brush]
    }

    # --------------------------------------------------------------------------
    Start-Group 'Oberfläche (XAML)'
    # --------------------------------------------------------------------------

    $xamlPfad = Join-Path $script:SrcDir 'Gui.xaml'
    $script:Fenster = $null

    Test-Case 'XAML ist wohlgeformtes XML' {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load($xamlPfad)
        $doc.DocumentElement.Name -eq 'Window'
    }
    Test-Case 'XAML lässt sich zu einem Fenster aufbauen' {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load($xamlPfad)
        $script:Fenster = [System.Windows.Markup.XamlReader]::Load(
            (New-Object System.Xml.XmlNodeReader -ArgumentList $doc))
        $null -ne $script:Fenster
    }
    Test-Case 'Alle Seiten und Navigationspunkte sind vorhanden' {
        $namen = @('NavDashboard','NavPorts','NavPresets','NavNat','NavHowTo','NavNetwork','NavSettings','NavAbout',
                   'PageDashboard','PagePorts','PagePresets','PageNat','PageHowTo','PageNetwork','PageSettings','PageAbout')
        $fehlt = @($namen | Where-Object { $null -eq $script:Fenster.FindName($_) })
        if ($fehlt.Count -eq 0) { return $true }
        return 'fehlt: ' + ($fehlt -join ', ')
    }
    Test-Case 'Keine fest verdrahtete Farbe im XAML' {
        # Sonst liesse sich das Element nicht mehr umfärben.
        $text = [System.IO.File]::ReadAllText($xamlPfad, [System.Text.Encoding]::UTF8)
        $treffer = [regex]::Matches($text, '(Background|Foreground|Fill|BorderBrush|Stroke)="#')
        if ($treffer.Count -eq 0) { return $true }
        return "$($treffer.Count) feste Farbwerte gefunden"
    }
    Test-Case 'Jeder DynamicResource-Schlüssel wird auch gesetzt' {
        # Gegen die Wirklichkeit prüfen statt gegen eine handgepflegte Liste:
        # ein Theme anwenden und schauen, was danach tatsächlich im Fenster
        # steht. So fällt ein neu erfundener Schlüssel sofort auf.
        Set-PortCheckTheme -Window $script:Fenster -Theme (Get-PortCheckThemes)[0]
        $gesetzt = @($script:Fenster.Resources.Keys | ForEach-Object { [string]$_ })

        $text = [System.IO.File]::ReadAllText($xamlPfad, [System.Text.Encoding]::UTF8)
        $benutzt = [regex]::Matches($text, 'DynamicResource\s+([A-Za-z0-9_]+)\s*\}') |
                   ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        $fehlt = @($benutzt | Where-Object { $gesetzt -notcontains $_ })
        if ($fehlt.Count -eq 0) { return $true }
        return 'nicht gesetzt: ' + ($fehlt -join ', ')
    }
    Test-Case 'Jede Farbwelt lässt sich auf das Fenster anwenden' {
        foreach ($t in (Get-PortCheckThemes)) {
            Set-PortCheckTheme -Window $script:Fenster -Theme $t
        }
        return $true
    }
    # --------------------------------------------------------------------------
    Start-Group 'Willkommensfenster'
    # --------------------------------------------------------------------------

    $welcomePfad = Join-Path $script:SrcDir 'Welcome.xaml'
    $script:WelcomeFenster = $null

    Test-Case 'Welcome.xaml ist vorhanden' { Test-Path $welcomePfad }
    Test-Case 'Welcome.xaml lässt sich zu einem Fenster aufbauen' {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load($welcomePfad)
        $script:WelcomeFenster = [System.Windows.Markup.XamlReader]::Load(
            (New-Object System.Xml.XmlNodeReader -ArgumentList $doc))
        $null -ne $script:WelcomeFenster
    }
    Test-Case 'Alle Bedienelemente des Willkommensfensters sind vorhanden' {
        $namen = @('WelcomeTitleBar', 'BtnWelcomeClose', 'BtnWelcomeStart',
                   'BtnWelcomeDiscord', 'BtnWelcomeLinktree', 'TxtWelcomeVersion')
        $fehlt = @($namen | Where-Object { $null -eq $script:WelcomeFenster.FindName($_) })
        if ($fehlt.Count -eq 0) { return $true }
        return 'fehlt: ' + ($fehlt -join ', ')
    }
    Test-Case 'Willkommensfenster nimmt jede Farbwelt an' {
        foreach ($t in (Get-PortCheckThemes)) {
            Set-PortCheckTheme -Window $script:WelcomeFenster -Theme $t
        }
        return $true
    }
    Test-Case 'Keine fest verdrahtete Farbe im Willkommensfenster' {
        $text = [System.IO.File]::ReadAllText($welcomePfad, [System.Text.Encoding]::UTF8)
        $treffer = [regex]::Matches($text, '(Background|Foreground|Fill|BorderBrush|Stroke)="#')
        if ($treffer.Count -eq 0) { return $true }
        return "$($treffer.Count) feste Farbwerte gefunden"
    }
    Test-Case 'Jeder DynamicResource-Schlüssel im Willkommensfenster wird gesetzt' {
        Set-PortCheckTheme -Window $script:WelcomeFenster -Theme (Get-PortCheckThemes)[0]
        $gesetzt = @($script:WelcomeFenster.Resources.Keys | ForEach-Object { [string]$_ })

        $text = [System.IO.File]::ReadAllText($welcomePfad, [System.Text.Encoding]::UTF8)
        $benutzt = [regex]::Matches($text, 'DynamicResource\s+([A-Za-z0-9_]+)\s*\}') |
                   ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        $fehlt = @($benutzt | Where-Object { $gesetzt -notcontains $_ })
        if ($fehlt.Count -eq 0) { return $true }
        return 'nicht gesetzt: ' + ($fehlt -join ', ')
    }

    # --------------------------------------------------------------------------
    Start-Group 'Name und Verweise'
    # --------------------------------------------------------------------------

    $guiText = [System.IO.File]::ReadAllText((Join-Path $script:SrcDir 'PortCheck.Gui.ps1'), [System.Text.Encoding]::UTF8)
    $cliText = [System.IO.File]::ReadAllText((Join-Path $script:SrcDir 'PortCheck.Cli.ps1'), [System.Text.Encoding]::UTF8)

    Test-Case 'Oberfläche und Konsole nennen dieselbe Version' {
        $a = [regex]::Match($guiText, "AppVersion\s*=\s*'([^']+)'").Groups[1].Value
        $b = [regex]::Match($cliText, "AppVersion\s*=\s*'([^']+)'").Groups[1].Value
        if ($a -and $a -eq $b) { return $true }
        return "GUI=$a CLI=$b"
    }
    Test-Case 'Oberfläche und Konsole nennen denselben Namen' {
        $a = [regex]::Match($guiText, "AppName\s*=\s*'([^']+)'").Groups[1].Value
        $b = [regex]::Match($cliText, "AppName\s*=\s*'([^']+)'").Groups[1].Value
        if ($a -and $a -eq $b) { return $true }
        return "GUI=$a CLI=$b"
    }
    Test-Case 'Discord- und Linktree-Adresse sind überall gleich' {
        $adressen = @{}
        foreach ($paar in @(@('DiscordUrl', 'discord.gg/teebug'), @('LinktreeUrl', 'linktr.ee/theersysending'))) {
            foreach ($quelle in @(@('GUI', $guiText), @('CLI', $cliText))) {
                $wert = [regex]::Match($quelle[1], "$($paar[0])\s*=\s*'([^']+)'").Groups[1].Value
                if ($wert -notlike "*$($paar[1])") { return "$($quelle[0])/$($paar[0]) = '$wert'" }
                $adressen["$($quelle[0])$($paar[0])"] = $wert
            }
        }
        return $true
    }
    Test-Case 'Alle Verweis-Schaltflächen sind im XAML vorhanden' {
        $namen = @('BtnLinktree', 'BtnDiscord', 'BtnSideDiscord', 'BtnSideLinktree',
                   'BtnAboutLinktree', 'BtnAboutDiscord', 'BtnAboutRepo', 'BtnShowWelcome', 'BtnPureVpn')
        $fehlt = @($namen | Where-Object { $null -eq $script:Fenster.FindName($_) })
        if ($fehlt.Count -eq 0) { return $true }
        return 'fehlt: ' + ($fehlt -join ', ')
    }
    Test-Case 'Jede Verweis-Schaltfläche hat einen Eintrag in der Zuordnung' {
        # Sonst klickt man ins Leere: der Handler schlägt über den Elementnamen nach.
        $karte = [regex]::Match($guiText, '\$script:LinkMap\s*=\s*@\{(?<inhalt>[\s\S]*?)\n\}').Groups['inhalt'].Value
        $fehlt = @()
        foreach ($n in @('BtnLinktree', 'BtnDiscord', 'BtnSideDiscord', 'BtnSideLinktree',
                         'BtnAboutLinktree', 'BtnAboutDiscord', 'BtnAboutRepo', 'BtnPureVpn')) {
            if ($karte -notlike "*'$n'*") { $fehlt += $n }
        }
        if ($fehlt.Count -eq 0) { return $true }
        return 'ohne Zuordnung: ' + ($fehlt -join ', ')
    }
    Test-Case 'Neue Einstellung WelcomeShown ist vorgesehen' {
        $guiText -match 'WelcomeShown'
    }
    Test-Case 'PureVPN-Verweis enthält die vollständige Empfehlungskennung' {
        # Angezeigt wird nur "PureVPN.com" - dahinter MUSS aber der komplette
        # Empfehlungslink stehen. Faellt die Kennung weg, verdient niemand mehr
        # daran, und es wuerde nicht auffallen.
        $url = [regex]::Match($guiText, "PureVpnUrl\s*=\s*'([^']+)'").Groups[1].Value
        if (-not $url) { return 'PureVpnUrl nicht gefunden' }
        if ($url -notlike 'https://www.purevpn.com/*') { return "unerwartete Adresse: $url" }
        if ($url -notmatch 'referrer=[A-Za-z0-9+/=]{40,}') { return 'Empfehlungskennung fehlt oder ist gekürzt' }
        return $true
    }
    Test-Case 'Der Werbe-Verweis ist als Werbung gekennzeichnet' {
        # Pflicht nach UWG - und ohne Kennzeichnung waere der Hinweis unlauter.
        $xamlText = [System.IO.File]::ReadAllText((Join-Path $script:SrcDir 'Gui.xaml'), [System.Text.Encoding]::UTF8)
        ($xamlText -match 'WERBUNG') -and ($xamlText -match 'Offenlegung')
    }

    Test-Case 'Preset-Karten schreiben ihre Auswahl ins Objekt zurück' {
        # Die Auswahl der Presets hängt daran, dass eine TwoWay-Bindung auf
        # eine Eigenschaft eines PowerShell-Objekts wirklich zurückschreibt.
        # Täte sie es nicht, liesse sich still nichts mehr auswählen.
        $objekt = [pscustomobject]@{ Name = 'Test'; IsSelected = $false }
        $schalter = New-Object System.Windows.Controls.Primitives.ToggleButton
        $schalter.DataContext = $objekt
        $bindung = New-Object System.Windows.Data.Binding 'IsSelected'
        $bindung.Mode = [System.Windows.Data.BindingMode]::TwoWay
        [void]$schalter.SetBinding(
            [System.Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty, $bindung)

        $schalter.IsChecked = $true
        if ($objekt.IsSelected -ne $true) { return 'Auswahl kam nicht am Objekt an' }
        $schalter.IsChecked = $false
        if ($objekt.IsSelected -ne $false) { return 'Abwahl kam nicht am Objekt an' }
        return $true
    }
}

# ------------------------------------------------------------------------------
# Region: Zusammenfassung
# ------------------------------------------------------------------------------

Write-Host ''
Write-Host ('  ' + ('=' * 68)) -ForegroundColor DarkCyan
$gesamt = $script:Bestanden + $script:Gescheitert
if ($script:Gescheitert -eq 0) {
    Write-Host "   ALLES GRÜN - $($script:Bestanden) von $gesamt Tests bestanden" -ForegroundColor Green
    Write-Host ('  ' + ('=' * 68)) -ForegroundColor DarkCyan
    Write-Host ''
    exit 0
} else {
    Write-Host "   $($script:Gescheitert) von $gesamt Tests GESCHEITERT" -ForegroundColor Red
    Write-Host ('  ' + ('=' * 68)) -ForegroundColor DarkCyan
    Write-Host ''
    exit 1
}
