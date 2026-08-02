#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - Diagnose
================================================================================
 Drei Dinge, die über den reinen Port-Test hinausgehen:

   1. Sicherheits-Check  - welche offenen Ports sind gefährlich und warum
   2. IPv6-Prüfung       - der Ausweg für alle, die bei IPv4 an CGNAT hängen
   3. Verbindungsqualität - wo in der Kette PC → Router → Anbieter → Internet
                            das Problem sitzt

 Wie überall im Projekt: keine Oberfläche, nur Objekte zurück.

 Lizenz: MIT (siehe LICENSE)
================================================================================
#>

# ------------------------------------------------------------------------------
# Region: Sicherheits-Check
# ------------------------------------------------------------------------------

function Get-RiskyPortCatalog {
    <#
    .SYNOPSIS
        Ports, die aus dem Internet erreichbar ein echtes Risiko darstellen.
    .DESCRIPTION
        Bewusst knapp gehalten und auf das beschränkt, was wirklich gefährlich
        ist. Zu jedem Eintrag steht, was ein Angreifer damit anfangen kann -
        eine Warnung ohne Begründung nimmt niemand ernst.

        Einstufung:
          Kritisch - wird aktiv und automatisiert angegriffen; gehört niemals
                     offen ins Internet
          Hoch     - Zugang zu Daten oder Konten, sobald ein Passwort fällt
          Mittel   - erhöht die Angriffsfläche, ist aber manchmal beabsichtigt
    #>
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Port=23;    Name='Telnet';            Severity='Kritisch'
            Why='Überträgt Benutzername und Passwort im Klartext. Wer mitliest, hat den Zugang. Es gibt keinen Grund, das aus dem Internet erreichbar zu haben.' }
        [pscustomobject]@{ Port=445;   Name='SMB / Windows-Freigaben'; Severity='Kritisch'
            Why='Wurde von WannaCry und NotPetya benutzt, um ganze Netze zu verschlüsseln. Offen im Internet ist das eine der gefährlichsten Fehlkonfigurationen überhaupt.' }
        [pscustomobject]@{ Port=135;   Name='Windows RPC';        Severity='Kritisch'
            Why='Gibt Auskunft über laufende Dienste und war wiederholt Einstiegspunkt für Würmer. Gehört ausschliesslich ins lokale Netz.' }
        [pscustomobject]@{ Port=139;   Name='NetBIOS';            Severity='Kritisch'
            Why='Alte Windows-Freigabetechnik. Verrät Rechner- und Benutzernamen und ist ein bekanntes Einfallstor.' }
        [pscustomobject]@{ Port=3389;  Name='Remotedesktop (RDP)'; Severity='Kritisch'
            Why='Wird rund um die Uhr automatisiert nach Passwörtern abgeklopft. Ein erfolgreicher Treffer bedeutet vollen Zugriff auf deinen Rechner. Wenn du RDP brauchst: über VPN, nie direkt.' }
        [pscustomobject]@{ Port=5900;  Name='VNC';                Severity='Kritisch'
            Why='Bildschirmfreigabe, oft ganz ohne oder mit sehr kurzem Passwort eingerichtet. Suchmaschinen für offene Geräte listen tausende davon.' }
        [pscustomobject]@{ Port=6379;  Name='Redis';              Severity='Kritisch'
            Why='Antwortet in der Standardeinstellung ohne jedes Passwort. Wird massenhaft gescannt und zum Einschleusen von Schadsoftware benutzt.' }
        [pscustomobject]@{ Port=2375;  Name='Docker-Schnittstelle'; Severity='Kritisch'
            Why='Ohne Verschlüsselung und ohne Anmeldung. Wer sie erreicht, kann beliebige Programme mit vollen Rechten starten.' }
        [pscustomobject]@{ Port=3306;  Name='MySQL / MariaDB';    Severity='Hoch'
            Why='Direkter Zugriff auf die Datenbank, sobald das Passwort bekannt oder schwach ist. Datenbanken gehören hinter die Anwendung, nicht ins Internet.' }
        [pscustomobject]@{ Port=1433;  Name='Microsoft SQL Server'; Severity='Hoch'
            Why='Wie MySQL: Datenbanken haben im Internet nichts verloren. Wird gezielt nach Standardpasswörtern durchsucht.' }
        [pscustomobject]@{ Port=5432;  Name='PostgreSQL';         Severity='Hoch'
            Why='Direkter Datenbankzugriff aus dem Internet.' }
        [pscustomobject]@{ Port=27017; Name='MongoDB';            Severity='Hoch'
            Why='War jahrelang ohne Passwort voreingestellt. Es gab reihenweise Fälle, in denen komplette Datenbestände abgegriffen wurden.' }
        [pscustomobject]@{ Port=9200;  Name='Elasticsearch';      Severity='Hoch'
            Why='Gibt in der Voreinstellung alle gespeicherten Daten heraus, ohne nach einem Passwort zu fragen.' }
        [pscustomobject]@{ Port=161;   Name='SNMP';               Severity='Hoch'
            Why='Viele Geräte antworten noch mit der Standardkennung "public" und geben dann bereitwillig ihre Konfiguration preis.' }
        [pscustomobject]@{ Port=21;    Name='FTP';                Severity='Hoch'
            Why='Zugangsdaten gehen im Klartext über die Leitung. Nutze SFTP oder FTPS.' }
        [pscustomobject]@{ Port=111;   Name='rpcbind / Portmapper'; Severity='Hoch'
            Why='Verrät, welche Dienste auf dem Rechner laufen, und wird für Verstärkungsangriffe missbraucht.' }
        [pscustomobject]@{ Port=22;    Name='SSH';                Severity='Mittel'
            Why='An sich sicher, wird aber pausenlos nach Passwörtern abgeklopft. Mit Schlüssel statt Passwort und abgeschalteter Root-Anmeldung vertretbar.' }
        [pscustomobject]@{ Port=25;    Name='SMTP';               Severity='Mittel'
            Why='Falsch eingerichtet wird daraus ein offener Mailverteiler, über den Fremde Spam verschicken - und deine Adresse landet auf Sperrlisten.' }
        [pscustomobject]@{ Port=8080;  Name='HTTP-Verwaltung';    Severity='Mittel'
            Why='Auf diesem Port sitzen häufig Verwaltungsoberflächen ohne Verschlüsselung. Prüfe, was dort tatsächlich läuft.' }
        [pscustomobject]@{ Port=8443;  Name='HTTPS-Verwaltung';   Severity='Mittel'
            Why='Wie 8080, nur verschlüsselt. Trotzdem: eine Verwaltungsoberfläche im Internet braucht ein starkes Passwort.' }
    )
}

function Get-SecurityAssessment {
    <#
    .SYNOPSIS
        Bewertet Messergebnisse gegen den Katalog gefährlicher Ports.
    .OUTPUTS
        Objekt mit Level ('Sauber'|'Hinweis'|'Warnung'|'Kritisch'), Findings,
        OpenCount, Summary
    #>
    [CmdletBinding()]
    param([object[]]$Results)

    $katalog = Get-RiskyPortCatalog
    $offen   = @($Results | Where-Object { $_.Status -eq 'Open' })
    $funde   = New-Object 'System.Collections.Generic.List[object]'

    foreach ($treffer in $offen) {
        $eintrag = @($katalog | Where-Object { $_.Port -eq $treffer.Port })
        if ($eintrag.Count -eq 0) { continue }
        $funde.Add([pscustomobject]@{
            Port     = $treffer.Port
            Name     = $eintrag[0].Name
            Severity = $eintrag[0].Severity
            Why      = $eintrag[0].Why
        })
    }

    $reihenfolge = @{ 'Kritisch' = 0; 'Hoch' = 1; 'Mittel' = 2 }
    $sortiert = @($funde.ToArray() | Sort-Object { $reihenfolge[$_.Severity] }, Port)

    $stufe = 'Sauber'
    if     (@($sortiert | Where-Object { $_.Severity -eq 'Kritisch' }).Count -gt 0) { $stufe = 'Kritisch' }
    elseif (@($sortiert | Where-Object { $_.Severity -eq 'Hoch' }).Count     -gt 0) { $stufe = 'Warnung' }
    elseif ($sortiert.Count -gt 0)                                                  { $stufe = 'Hinweis' }

    $zusammenfassung = switch ($stufe) {
        'Kritisch' { "$($sortiert.Count) gefährliche(r) Port(s) offen - darunter mindestens einer, der aktiv angegriffen wird. Hier solltest du zeitnah etwas tun." }
        'Warnung'  { "$($sortiert.Count) Port(s) offen, die nicht ins Internet gehören. Kein Notfall, aber unnötiges Risiko." }
        'Hinweis'  { "$($sortiert.Count) Port(s) offen, die die Angriffsfläche erhöhen. Prüfe, ob das so gewollt ist." }
        default    { 'Keiner der geprüften Ports steht auf der Risikoliste. Das ist der Normalfall und gut so.' }
    }

    [pscustomobject]@{
        Level     = $stufe
        Findings  = $sortiert
        OpenCount = $offen.Count
        Summary   = $zusammenfassung
    }
}

function Get-SecurityScanPorts {
    <#
    .SYNOPSIS
        Die Portliste für den Sicherheits-Durchlauf.
    #>
    [CmdletBinding()]
    param()
    return @(Get-RiskyPortCatalog | ForEach-Object { $_.Port } | Sort-Object -Unique)
}

# ------------------------------------------------------------------------------
# Region: IPv6
# ------------------------------------------------------------------------------

function Get-IPv6Status {
    <#
    .SYNOPSIS
        Prüft, ob dieser Anschluss über IPv6 im Internet erreichbar ist.
    .DESCRIPTION
        Für alle, denen der IPv4-Test wegen CGNAT nichts bringt, ist das die
        eigentlich wichtige Frage. Bei DS-Lite gibt es natives IPv6 - und
        darüber ist jedes Gerät direkt adressierbar, ganz ohne Portweiterleitung.

        Geprüft wird zweierlei:
          - hat dieser Rechner eine global gültige IPv6-Adresse?
          - kommt darüber tatsächlich eine Verbindung ins Internet zustande?

        Beides ist nötig: eine Adresse allein sagt nichts, wenn der Router
        IPv6 nicht weiterleitet.
    .OUTPUTS
        Objekt mit HasGlobalAddress, LocalAddresses, InternetWorks, PublicAddress,
        Level, Title, Reasons
    #>
    [CmdletBinding()]
    param([int]$TimeoutSec = 8)

    $adressen = @()
    try {
        $adressen = @(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop |
                      Where-Object {
                          $_.IPAddress -notlike 'fe80*' -and     # nur lokal gültig
                          $_.IPAddress -ne '::1' -and            # Loopback
                          $_.IPAddress -notlike 'fd*' -and       # privater Bereich
                          $_.IPAddress -notlike 'fc*'
                      } |
                      Select-Object -ExpandProperty IPAddress)
    } catch {
        # .NET-Rückfallweg für Systeme ohne die Net-Cmdlets
        try {
            foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
                if ($nic.OperationalStatus -ne 'Up') { continue }
                foreach ($eintrag in $nic.GetIPProperties().UnicastAddresses) {
                    $a = $eintrag.Address
                    if ($a.AddressFamily -ne 'InterNetworkV6') { continue }
                    if ($a.IsIPv6LinkLocal -or $a.IsIPv6SiteLocal -or $a.ToString() -eq '::1') { continue }
                    $adressen += $a.ToString()
                }
            }
        } catch { }
    }
    $adressen = @($adressen | Select-Object -Unique)

    # Nur über IPv6 erreichbare Dienste - antwortet einer, steht IPv6 wirklich.
    $öffentlich = $null
    foreach ($url in @('https://api6.ipify.org', 'https://v6.ident.me', 'https://ipv6.icanhazip.com')) {
        try {
            $roh = Invoke-RestMethod -Uri $url -TimeoutSec $TimeoutSec -UserAgent $script:PcUserAgent
            $wert = ([string]$roh).Trim()
            if ($wert -match ':') { $öffentlich = $wert; break }
        } catch { }
    }

    $funktioniert = [bool]$öffentlich
    $hatAdresse   = ($adressen.Count -gt 0)

    $ergebnis = [ordered]@{
        HasGlobalAddress = $hatAdresse
        LocalAddresses   = $adressen
        InternetWorks    = $funktioniert
        PublicAddress    = $öffentlich
        Level            = 'None'
        Title            = 'Kein IPv6'
        Reasons          = @()
    }

    if ($funktioniert) {
        $ergebnis.Level   = 'Full'
        $ergebnis.Title   = 'IPv6 vorhanden'
        $ergebnis.Reasons = @(
            'Dein Anschluss ist über IPv6 im Internet unterwegs.',
            'Über IPv6 hat jedes Gerät eine eigene, weltweit gültige Adresse - eine Portweiterleitung wie bei IPv4 gibt es hier gar nicht.',
            'Wenn dein IPv4 an CGNAT hängt, ist das dein Ausweg: Mitspieler und Server, die IPv6 können, erreichen dich direkt.',
            'Voraussetzung bleibt, dass die Firewall im Router den gewünschten Port für dieses Gerät durchlässt. Der Menüpunkt heisst je nach Hersteller "IPv6-Freigabe", "Firewall-Regel" oder "Pinhole".',
            'Wermutstropfen: die Gegenstelle muss ebenfalls IPv6 haben. Viele Spiele-Server und Mobilfunknetze können es noch nicht.'
        )
    } elseif ($hatAdresse) {
        $ergebnis.Level   = 'Partial'
        $ergebnis.Title   = 'IPv6 nur halb da'
        $ergebnis.Reasons = @(
            'Dieser Rechner hat eine global gültige IPv6-Adresse, es kommt darüber aber keine Verbindung ins Internet zustande.',
            'Typische Ursachen: der Router leitet IPv6 nicht weiter, die IPv6-Firewall blockiert alles, oder der Anbieter hat IPv6 nicht freigeschaltet.',
            'Ein Blick in die Router-Einstellungen unter "IPv6" lohnt sich.'
        )
    } else {
        $ergebnis.Level   = 'None'
        $ergebnis.Title   = 'Kein IPv6'
        $ergebnis.Reasons = @(
            'Dieser Rechner hat keine global gültige IPv6-Adresse.',
            'Entweder unterstützt dein Anbieter kein IPv6, oder es ist im Router abgeschaltet.',
            'Hängst du bei IPv4 an CGNAT, wäre eingeschaltetes IPv6 der einfachste Ausweg - frag beim Anbieter nach.'
        )
    }

    return [pscustomobject]$ergebnis
}

# ------------------------------------------------------------------------------
# Region: Verbindungsqualität
# ------------------------------------------------------------------------------

function Measure-Latency {
    <#
    .SYNOPSIS
        Misst Antwortzeit, Schwankung und Paketverlust zu einem Ziel.
    .DESCRIPTION
        Die Schwankung (Jitter) ist beim Spielen oft wichtiger als die reine
        Antwortzeit: gleichmässige 60 ms fühlen sich besser an als 30 ms, die
        ständig auf 120 springen.

        Gerechnet wird als mittlerer Abstand zwischen aufeinanderfolgenden
        Messungen - das bildet genau dieses Springen ab.
    .OUTPUTS
        Objekt mit Target, Sent, Received, LossPercent, MinMs, AvgMs, MaxMs,
        JitterMs, Reachable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [int]$Count = 10,
        [int]$TimeoutMs = 1200,
        [int]$PauseMs = 120
    )

    $ping   = New-Object System.Net.NetworkInformation.Ping
    $zeiten = New-Object 'System.Collections.Generic.List[double]'
    $verlust = 0

    for ($i = 0; $i -lt $Count; $i++) {
        try {
            $antwort = $ping.Send($Target, $TimeoutMs)
            if ($antwort.Status -eq 'Success') { $zeiten.Add([double]$antwort.RoundtripTime) }
            else { $verlust++ }
        } catch {
            $verlust++
        }
        if ($i -lt $Count - 1) { Start-Sleep -Milliseconds $PauseMs }
    }
    try { $ping.Dispose() } catch { }

    $werte = $zeiten.ToArray()
    if ($werte.Count -eq 0) {
        return [pscustomobject]@{
            Target = $Target; Sent = $Count; Received = 0; LossPercent = 100
            MinMs = 0; AvgMs = 0; MaxMs = 0; JitterMs = 0; Reachable = $false
        }
    }

    $jitter = 0.0
    if ($werte.Count -gt 1) {
        $summe = 0.0
        for ($i = 1; $i -lt $werte.Count; $i++) { $summe += [Math]::Abs($werte[$i] - $werte[$i - 1]) }
        $jitter = $summe / ($werte.Count - 1)
    }

    [pscustomobject]@{
        Target      = $Target
        Sent        = $Count
        Received    = $werte.Count
        LossPercent = [math]::Round(100.0 * $verlust / $Count, 1)
        MinMs       = [math]::Round(($werte | Measure-Object -Minimum).Minimum, 0)
        AvgMs       = [math]::Round(($werte | Measure-Object -Average).Average, 0)
        MaxMs       = [math]::Round(($werte | Measure-Object -Maximum).Maximum, 0)
        JitterMs    = [math]::Round($jitter, 1)
        Reachable   = $true
    }
}

function Get-LatencyRating {
    <#
    .SYNOPSIS
        Übersetzt Messwerte in eine Einschätzung fürs Spielen.
    .OUTPUTS
        Objekt mit Level ('Sehr gut'|'Gut'|'Brauchbar'|'Schlecht'|'Unerreichbar'),
        Text
    #>
    [CmdletBinding()]
    param($Measurement)

    if (-not $Measurement.Reachable) {
        return [pscustomobject]@{ Level = 'Unerreichbar'; Text = 'Keine Antwort. Das Ziel blockiert Ping, oder die Verbindung dorthin steht nicht.' }
    }
    if ($Measurement.LossPercent -ge 5) {
        return [pscustomobject]@{ Level = 'Schlecht'; Text = "$($Measurement.LossPercent) % Paketverlust. Das reisst Verbindungen ab und lässt Spiele ruckeln - hier liegt ein echtes Problem." }
    }
    if ($Measurement.LossPercent -gt 0) {
        return [pscustomobject]@{ Level = 'Brauchbar'; Text = "$($Measurement.LossPercent) % Paketverlust. Wenig, aber beim Spielen spürbar." }
    }
    if ($Measurement.JitterMs -ge 30) {
        return [pscustomobject]@{ Level = 'Schlecht'; Text = "Starke Schwankung ($($Measurement.JitterMs) ms). Fühlt sich schlechter an als eine gleichmässig hohe Antwortzeit." }
    }
    if ($Measurement.JitterMs -ge 12) {
        return [pscustomobject]@{ Level = 'Brauchbar'; Text = "Spürbare Schwankung ($($Measurement.JitterMs) ms)." }
    }
    if ($Measurement.AvgMs -le 30)  { return [pscustomobject]@{ Level = 'Sehr gut';  Text = 'Niedrig und gleichmässig - besser wird es nicht.' } }
    if ($Measurement.AvgMs -le 70)  { return [pscustomobject]@{ Level = 'Gut';       Text = 'Für alle Spielarten ausreichend.' } }
    if ($Measurement.AvgMs -le 120) { return [pscustomobject]@{ Level = 'Brauchbar'; Text = 'Bei schnellen Shootern merkbar, sonst unkritisch.' } }
    return [pscustomobject]@{ Level = 'Schlecht'; Text = 'Hohe Antwortzeit. Bei schnellen Spielen deutlich im Nachteil.' }
}

function Get-NetworkPathTargets {
    <#
    .SYNOPSIS
        Die Messkette vom eigenen Rechner bis ins Internet.
    .DESCRIPTION
        Der Sinn liegt in der Reihenfolge: erst der Router, dann der Anbieter,
        dann das offene Internet. Wo die Werte zum ersten Mal schlecht werden,
        dort sitzt das Problem.

        Das ist ehrlicher als ein angeblicher "Ping zum Spieleserver": die
        meisten Spieleserver beantworten gar keine Ping-Anfragen, ein solcher
        Wert wäre erfunden.
    #>
    [CmdletBinding()]
    param([string]$Gateway, [string]$Dns)

    $ziele = New-Object 'System.Collections.Generic.List[object]'

    if ($Gateway) {
        $ziele.Add([pscustomobject]@{
            Label = 'Dein Router'; Host = $Gateway
            Meaning = 'Nur dein Heimnetz. Schwankt es schon hier, liegt es an WLAN, Kabel oder Router - nicht am Anbieter.'
        })
    }
    if ($Dns -and $Dns -ne $Gateway) {
        $ziele.Add([pscustomobject]@{
            Label = 'Dein DNS-Server'; Host = $Dns
            Meaning = 'Meist der erste Rechner beim Anbieter. Zeigt die Qualität deiner Anschlussleitung.'
        })
    }
    $ziele.Add([pscustomobject]@{
        Label = 'Cloudflare'; Host = '1.1.1.1'
        Meaning = 'Nächstgelegener Knotenpunkt eines weltweiten Netzes. Der Richtwert für deine allgemeine Verbindung.'
    })
    $ziele.Add([pscustomobject]@{
        Label = 'Google'; Host = '8.8.8.8'
        Meaning = 'Zweiter Richtwert. Weicht er stark von Cloudflare ab, hakt es an der Wegführung deines Anbieters.'
    })
    $ziele.Add([pscustomobject]@{
        Label = 'Quad9 (Europa)'; Host = '9.9.9.9'
        Meaning = 'Dritter Vergleichswert für europäische Ziele.'
    })

    return $ziele.ToArray()
}
