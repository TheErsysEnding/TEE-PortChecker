#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - UPnP-Steuerung (Internet Gateway Device)
================================================================================
 Damit kann das Werkzeug Portfreigaben im Router nicht nur erkennen, sondern
 auch anlegen und wieder entfernen - ohne dass jemand das Router-Menü sucht.

 SO LÄUFT DAS AB:
   1. Per SSDP wird der Router gefunden (siehe Get-UpnpDevices im Core).
      Seine Antwort enthält eine LOCATION-Adresse.
   2. Unter dieser Adresse liegt eine XML-Beschreibung des Geräts mit allen
      Diensten. Gesucht wird WANIPConnection oder WANPPPConnection - das ist
      der Dienst, der Portweiterleitungen verwaltet.
   3. An dessen Steuer-Adresse gehen dann SOAP-Aufrufe: auflisten, anlegen,
      löschen.

 EHRLICHE EINORDNUNG:
   - Nicht jeder Router kann das, und viele haben UPnP ab Werk abgeschaltet.
     Ohne UPnP bleibt nur der Weg über das Router-Menü.
   - UPnP kennt keine Anmeldung. Jedes Programm im Heimnetz darf Ports öffnen -
     auch Schadsoftware. Genau deshalb schalten manche es bewusst ab, und
     genau deshalb zeigt dieses Werkzeug vorhandene Freigaben an: da steht
     manchmal Überraschendes drin.
   - Eine Freigabe öffnet einen Weg aus dem Internet zu deinem Rechner. Das
     Programm fragt vorher nach und bietet das Entfernen mit einem Klick an.

 Lizenz: MIT (siehe LICENSE)
================================================================================
#>

$script:UpnpDienstTypen = @(
    'urn:schemas-upnp-org:service:WANIPConnection:2',
    'urn:schemas-upnp-org:service:WANIPConnection:1',
    'urn:schemas-upnp-org:service:WANPPPConnection:1'
)

function Get-UpnpControlPoint {
    <#
    .SYNOPSIS
        Ermittelt aus der Geräte-Beschreibung die Steuer-Adresse für
        Portweiterleitungen.
    .PARAMETER Location
        Die LOCATION-Adresse aus der SSDP-Antwort, z. B.
        http://192.168.1.1:49000/igddesc.xml
    .OUTPUTS
        Objekt mit ControlUrl, ServiceType, DeviceName, BaseUrl - oder $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Location,
        [int]$TimeoutSec = 8
    )

    try {
        $antwort = Invoke-WebRequest -Uri $Location -TimeoutSec $TimeoutSec -UseBasicParsing
        $xml = [xml]$antwort.Content
    } catch {
        return $null
    }

    $basis = $Location
    try {
        $u = [System.Uri]$Location
        $basis = "$($u.Scheme)://$($u.Authority)"
    } catch { }

    # URLBase überschreibt die abgeleitete Basis, wenn vorhanden.
    try {
        if ($xml.root.URLBase) { $basis = ([string]$xml.root.URLBase).TrimEnd('/') }
    } catch { }

    $geraeteName = ''
    try { $geraeteName = [string]$xml.root.device.friendlyName } catch { }

    # Alle Dienste im Baum einsammeln - sie stecken verschachtelt in
    # deviceList/device/serviceList/service.
    $dienste = @($xml.GetElementsByTagName('service'))

    foreach ($typ in $script:UpnpDienstTypen) {
        foreach ($dienst in $dienste) {
            $dienstTyp = ''
            $steuerUrl = ''
            try { $dienstTyp = [string]$dienst.serviceType } catch { }
            try { $steuerUrl = [string]$dienst.controlURL } catch { }
            if ($dienstTyp -ne $typ -or -not $steuerUrl) { continue }

            if ($steuerUrl -notmatch '^https?://') {
                if (-not $steuerUrl.StartsWith('/')) { $steuerUrl = '/' + $steuerUrl }
                $steuerUrl = $basis.TrimEnd('/') + $steuerUrl
            }

            return [pscustomobject]@{
                ControlUrl  = $steuerUrl
                ServiceType = $dienstTyp
                DeviceName  = $geraeteName
                BaseUrl     = $basis
            }
        }
    }
    return $null
}

function Invoke-UpnpAction {
    <#
    .SYNOPSIS
        Führt einen SOAP-Aufruf gegen den Router aus.
    .DESCRIPTION
        Gibt bei Erfolg das Antwort-XML zurück. Scheitert der Aufruf, wird die
        Fehlernummer des Routers mitgeliefert - die sagt oft genauer, woran es
        lag, als die HTTP-Meldung (z. B. 718 = Weiterleitung existiert bereits).
    .OUTPUTS
        Objekt mit Success, Xml, ErrorCode, ErrorText
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ControlPoint,
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$Arguments = @{},
        [int]$TimeoutSec = 10
    )

    $argumentXml = ''
    foreach ($schluessel in $Arguments.Keys) {
        $wert = [System.Security.SecurityElement]::Escape([string]$Arguments[$schluessel])
        $argumentXml += "<$schluessel>$wert</$schluessel>"
    }

    $umschlag = @"
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body><u:$Action xmlns:u="$($ControlPoint.ServiceType)">$argumentXml</u:$Action></s:Body>
</s:Envelope>
"@

    # Bewusst HttpWebRequest statt Invoke-WebRequest.
    #
    # Der Grund: bei einem Fehler antwortet der Router mit HTTP 500 UND einem
    # SOAP-Fault im Körper, in dem die eigentliche Ursache steht (718 = Port
    # schon vergeben, 714 = gibt es nicht, ...). Invoke-WebRequest hat den
    # Körper zu diesem Zeitpunkt aber bereits verbraucht - ein späteres
    # GetResponseStream() liefert null Bytes. Die Fehlernummer waere damit
    # verloren, und jede Ablehnung stuende als nichtssagendes "Fehler 0" da.
    # Nachgemessen und in der Testsuite abgesichert.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($umschlag)

    try {
        $anfrage = [System.Net.HttpWebRequest]::Create($ControlPoint.ControlUrl)
        $anfrage.Method      = 'POST'
        $anfrage.ContentType = 'text/xml; charset="utf-8"'
        $anfrage.Timeout     = $TimeoutSec * 1000
        $anfrage.UserAgent   = 'TEE-PortChecker/1.0'
        $anfrage.Headers.Add('SOAPAction', "`"$($ControlPoint.ServiceType)#$Action`"")
        $anfrage.ContentLength = $bytes.Length

        $ausgang = $anfrage.GetRequestStream()
        try { $ausgang.Write($bytes, 0, $bytes.Length) } finally { $ausgang.Dispose() }
    } catch {
        return [pscustomobject]@{
            Success = $false; Xml = $null; ErrorCode = 0
            ErrorText = "Der Router war nicht erreichbar: $($_.Exception.Message)"
        }
    }

    $inhalt = ''
    try {
        $antwort = $anfrage.GetResponse()
        try {
            $leser  = New-Object System.IO.StreamReader($antwort.GetResponseStream())
            $inhalt = $leser.ReadToEnd()
            $leser.Dispose()
        } finally { $antwort.Close() }
    } catch [System.Net.WebException] {
        $code = 0
        $text = $_.Exception.Message
        try {
            $fehlerAntwort = $_.Exception.Response
            if ($fehlerAntwort) {
                $leser = New-Object System.IO.StreamReader($fehlerAntwort.GetResponseStream())
                $fehlerText = $leser.ReadToEnd()
                $leser.Dispose()
                $fehlerAntwort.Close()
                if ($fehlerText -match '<errorCode>(\d+)</errorCode>')          { $code = [int]$Matches[1] }
                if ($fehlerText -match '<errorDescription>([^<]*)</errorDescription>') { $text = $Matches[1] }
            }
        } catch { }
        return [pscustomobject]@{ Success = $false; Xml = $null; ErrorCode = $code; ErrorText = $text }
    } catch {
        return [pscustomobject]@{
            Success = $false; Xml = $null; ErrorCode = 0; ErrorText = $_.Exception.Message
        }
    }

    # Das Auswerten der Antwort ist bewusst getrennt: eine unlesbare Antwort
    # ist etwas anderes als eine Ablehnung durch den Router.
    try {
        return [pscustomobject]@{
            Success = $true; Xml = [xml]$inhalt; ErrorCode = 0; ErrorText = ''
        }
    } catch {
        return [pscustomobject]@{
            Success = $false; Xml = $null; ErrorCode = -1
            ErrorText = "Der Router hat geantwortet, die Antwort war aber kein lesbares XML: $($_.Exception.Message)"
        }
    }
}

function Get-UpnpNodeText {
    <#
    .SYNOPSIS
        Liest den Textinhalt eines Knotens aus einer SOAP-Antwort.
    .DESCRIPTION
        Über GetElementsByTagName statt über den Pfad, weil die Router die
        Antwort unterschiedlich verschachteln und teils eigene Namensräume
        verwenden.
    #>
    [CmdletBinding()]
    param($Xml, [string]$Name)
    try {
        $knoten = $Xml.GetElementsByTagName($Name)
        if ($knoten.Count -gt 0) { return [string]$knoten[0].InnerText }
    } catch { }
    return ''
}

function Get-UpnpExternalAddress {
    <#
    .SYNOPSIS
        Fragt den Router, welche öffentliche Adresse er nach außen hat.
    .DESCRIPTION
        Aufschlussreich im Vergleich mit der per HTTP ermittelten Adresse:
        weichen beide ab, hängt noch etwas dazwischen - ein zweiter Router,
        CGNAT beim Anbieter oder ein VPN.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$ControlPoint)

    $ergebnis = Invoke-UpnpAction -ControlPoint $ControlPoint -Action 'GetExternalIPAddress'
    if (-not $ergebnis.Success) { return $null }
    try {
        $knoten = $ergebnis.Xml.GetElementsByTagName('NewExternalIPAddress')
        if ($knoten.Count -gt 0) { return [string]$knoten[0].InnerText }
    } catch { }
    return $null
}

function Get-UpnpPortMappings {
    <#
    .SYNOPSIS
        Listet alle Portweiterleitungen auf, die im Router eingetragen sind.
    .DESCRIPTION
        Der Router kennt keine "gib mir alle"-Abfrage. Man fragt Eintrag 0, 1,
        2 ... ab, bis er einen Fehler meldet - dann ist das Ende erreicht.
        MaxEntries verhindert eine Endlosschleife bei Geräten, die statt eines
        Fehlers immer weiter antworten.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ControlPoint,
        [int]$MaxEntries = 60,
        [scriptblock]$OnProgress
    )

    $liste = New-Object 'System.Collections.Generic.List[object]'

    for ($i = 0; $i -lt $MaxEntries; $i++) {
        if ($OnProgress) { & $OnProgress $i }
        $ergebnis = Invoke-UpnpAction -ControlPoint $ControlPoint `
                        -Action 'GetGenericPortMappingEntry' `
                        -Arguments @{ NewPortMappingIndex = $i }
        if (-not $ergebnis.Success) { break }

        $extern = Get-UpnpNodeText -Xml $ergebnis.Xml -Name 'NewExternalPort'
        if (-not $extern) { break }

        $laufzeit = Get-UpnpNodeText -Xml $ergebnis.Xml -Name 'NewLeaseDuration'
        if ($laufzeit -notmatch '^\d+$') { $laufzeit = '0' }

        $liste.Add([pscustomobject]@{
            ExternalPort = [int]$extern
            InternalPort = [int](Get-UpnpNodeText -Xml $ergebnis.Xml -Name 'NewInternalPort')
            Protocol     = (Get-UpnpNodeText -Xml $ergebnis.Xml -Name 'NewProtocol')
            Client       = (Get-UpnpNodeText -Xml $ergebnis.Xml -Name 'NewInternalClient')
            Description  = (Get-UpnpNodeText -Xml $ergebnis.Xml -Name 'NewPortMappingDescription')
            Enabled      = ((Get-UpnpNodeText -Xml $ergebnis.Xml -Name 'NewEnabled') -eq '1')
            LeaseSeconds = [int]$laufzeit
        })
    }

    return $liste.ToArray()
}

function Add-UpnpPortMapping {
    <#
    .SYNOPSIS
        Legt eine Portweiterleitung im Router an.
    .DESCRIPTION
        ACHTUNG: Damit wird ein Weg aus dem Internet zu diesem Rechner geöffnet.
        Die Oberfläche fragt vorher nach und bietet das Entfernen an.

        LeaseSeconds = 0 bedeutet dauerhaft. Manche Router lehnen 0 ab und
        verlangen eine Laufzeit - deshalb wird bei Fehler 402/725 ein zweiter
        Versuch mit einer Laufzeit unternommen.
    .OUTPUTS
        Objekt mit Success, Message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ControlPoint,
        [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$ExternalPort,
        [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$InternalPort,
        [Parameter(Mandatory = $true)][string]$InternalClient,
        [ValidateSet('TCP', 'UDP')][string]$Protocol = 'TCP',
        [string]$Description = 'TEE PortChecker',
        [int]$LeaseSeconds = 0
    )

    $argumente = @{
        NewRemoteHost             = ''
        NewExternalPort           = $ExternalPort
        NewProtocol               = $Protocol
        NewInternalPort           = $InternalPort
        NewInternalClient         = $InternalClient
        NewEnabled                = 1
        NewPortMappingDescription = $Description
        NewLeaseDuration          = $LeaseSeconds
    }

    $ergebnis = Invoke-UpnpAction -ControlPoint $ControlPoint -Action 'AddPortMapping' -Arguments $argumente

    # Manche Geräte mögen keine unbefristete Weiterleitung.
    if (-not $ergebnis.Success -and $LeaseSeconds -eq 0 -and
        ($ergebnis.ErrorCode -eq 402 -or $ergebnis.ErrorCode -eq 725)) {
        $argumente.NewLeaseDuration = 604800      # eine Woche
        $ergebnis = Invoke-UpnpAction -ControlPoint $ControlPoint -Action 'AddPortMapping' -Arguments $argumente
    }

    if ($ergebnis.Success) {
        return [pscustomobject]@{ Success = $true; Message = "Port $ExternalPort/$Protocol wurde im Router freigegeben." }
    }

    $meldung = switch ($ergebnis.ErrorCode) {
        718     { "Port $ExternalPort/$Protocol ist bereits an ein anderes Gerät vergeben." }
        724     { 'Der Router erlaubt nur gleiche interne und externe Portnummern.' }
        725     { 'Der Router verlangt eine befristete Freigabe und hat auch den zweiten Versuch abgelehnt.' }
        726     { 'Der Router erlaubt keine Freigabe für beliebige Gegenstellen.' }
        401     { 'Der Router kennt diesen Befehl nicht - UPnP-Portfreigabe wird nicht unterstützt.' }
        606     { 'Der Router hat die Aktion abgelehnt (nicht berechtigt). UPnP ist eventuell nur eingeschränkt erlaubt.' }
        default { "Der Router hat abgelehnt (Fehler $($ergebnis.ErrorCode)): $($ergebnis.ErrorText)" }
    }
    return [pscustomobject]@{ Success = $false; Message = $meldung }
}

function Remove-UpnpPortMapping {
    <#
    .SYNOPSIS
        Entfernt eine Portweiterleitung wieder aus dem Router.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ControlPoint,
        [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$ExternalPort,
        [ValidateSet('TCP', 'UDP')][string]$Protocol = 'TCP'
    )

    $ergebnis = Invoke-UpnpAction -ControlPoint $ControlPoint -Action 'DeletePortMapping' -Arguments @{
        NewRemoteHost   = ''
        NewExternalPort = $ExternalPort
        NewProtocol     = $Protocol
    }

    if ($ergebnis.Success) {
        return [pscustomobject]@{ Success = $true; Message = "Freigabe für Port $ExternalPort/$Protocol wurde entfernt." }
    }
    if ($ergebnis.ErrorCode -eq 714) {
        return [pscustomobject]@{ Success = $false; Message = "Für Port $ExternalPort/$Protocol gibt es gar keine Freigabe." }
    }
    return [pscustomobject]@{
        Success = $false
        Message = "Entfernen fehlgeschlagen (Fehler $($ergebnis.ErrorCode)): $($ergebnis.ErrorText)"
    }
}

function Connect-UpnpRouter {
    <#
    .SYNOPSIS
        Sucht den Router und liefert einen einsatzbereiten Steuerpunkt.
    .DESCRIPTION
        Fasst SSDP-Suche und das Auswerten der Geräte-Beschreibung zusammen -
        das ist der übliche Einstieg für die Oberfläche.
    .OUTPUTS
        Objekt mit Found, ControlPoint, DeviceName, Address, Message
    #>
    [CmdletBinding()]
    param([int]$TimeoutMs = 3500)

    $geraete = Get-UpnpDevices -TimeoutMs $TimeoutMs
    if (@($geraete).Count -eq 0) {
        # Erst die häufigste Ursache prüfen, bevor dem Router die Schuld
        # gegeben wird: in der Netzwerkkategorie "Öffentlich" blockt die
        # Windows-Firewall die Antworten auf SSDP. Die Suche kann dann gar
        # nichts finden, egal was der Router könnte.
        $netz = Get-NetworkCategory
        if ($netz.IsPublic) {
            return [pscustomobject]@{
                Found = $false; ControlPoint = $null; DeviceName = ''; Address = ''
                Message = "Windows stuft dein Netzwerk ($($netz.InterfaceAlias)) als OEFFENTLICH ein. " +
                          'In dieser Einstufung blockiert die Windows-Firewall die Antworten des Routers, ' +
                          'die UPnP-Suche kann deshalb nichts finden - unabhaengig davon, was dein Router kann. ' +
                          'Abhilfe: Einstellungen > Netzwerk und Internet > WLAN bzw. Ethernet > Netzwerkprofiltyp ' +
                          'auf "Privat" stellen. Das gilt nur für dein Heimnetz.'
            }
        }
        return [pscustomobject]@{
            Found = $false; ControlPoint = $null; DeviceName = ''; Address = ''
            Message = 'Kein UPnP-Router gefunden. Entweder ist UPnP im Router abgeschaltet, oder er antwortet nicht auf SSDP.'
        }
    }

    foreach ($geraet in $geraete) {
        if (-not $geraet.Location) { continue }
        $steuerpunkt = Get-UpnpControlPoint -Location $geraet.Location
        if ($steuerpunkt) {
            return [pscustomobject]@{
                Found        = $true
                ControlPoint = $steuerpunkt
                DeviceName   = $(if ($steuerpunkt.DeviceName) { $steuerpunkt.DeviceName } else { $geraet.Server })
                Address      = $geraet.Address
                Message      = ''
            }
        }
    }

    return [pscustomobject]@{
        Found = $false; ControlPoint = $null; DeviceName = ''; Address = @($geraete)[0].Address
        Message = 'Der Router antwortet auf UPnP, bietet aber keinen Dienst für Portweiterleitungen an.'
    }
}
