#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - Engine ohne jede Oberfläche
================================================================================
 Dieses Modul enthält die gesamte Logik: öffentliche IP ermitteln, TCP-Ports
 von außen prüfen, NAT-Typ per STUN bestimmen, UPnP/SSDP-Router finden.

 Es gibt hier bewusst KEIN Write-Host und KEINE Fenster. Jede Funktion gibt
 Objekte zurück. Dadurch können GUI, CLI und ein Hintergrund-Runspace
 exakt denselben Code benutzen - was ihr seht ist was läuft.

 Lizenz: MIT (siehe LICENSE)
 Projekt: https://github.com/TheErsysEnding/TEE-PortChecker
================================================================================
#>

# Hinweis: Set-StrictMode steht bewusst NUR in den Einstiegspunkten
# (PortCheck.Gui.ps1 / PortCheck.Cli.ps1). Der Modus wirkt dynamisch auf den
# Aufrufer - eine Bibliothek darf die Session dessen, der sie dot-sourced,
# nicht heimlich umstellen.

<#
 HINWEIS - @() um List[object] herum vermeiden

 Auf mindestens einem aktuellen PowerShell-5.1-Build (5.1.26100) wirft

     @($eineListeVomTyp_List_object)

 die Ausnahme "Die Argumenttypen stimmen nicht überein". Nur genau dieser
 eine Typ ist betroffen - List[string], List[int], SortedSet, HashSet,
 ArrayList und ObservableCollection funktionieren einwandfrei.

 Deshalb wird hier überall .ToArray() benutzt. Das ist ohnehin die
 eindeutigere Schreibweise und läuft auf jeder Version.
 Die Testsuite prüft dieses Verhalten ab (tests/Run-Tests.ps1).
#>

# TLS 1.2 erzwingen - ältere Windows-Installationen nutzen sonst TLS 1.0
# und scheitern an modernen HTTPS-Diensten.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
} catch { }

# Manche Dienste blocken den PowerShell-Standard-UserAgent.
$script:PcUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) TEE-PortChecker/1.0 (+https://github.com/TheErsysEnding/TEE-PortChecker)'

# ------------------------------------------------------------------------------
# Region: Adressen & Netzwerk-Basisinfos
# ------------------------------------------------------------------------------

function Get-PublicIPAddress {
    <#
    .SYNOPSIS
        Ermittelt die öffentliche IPv4-Adresse über mehrere unabhängige Dienste.
    .DESCRIPTION
        Fragt der Reihe nach mehrere Anbieter. Der erste, der eine gültige IPv4
        liefert, gewinnt. Gibt $null zurück, wenn keiner erreichbar ist.
        Es werden dabei KEINE Daten außer der bloßen Anfrage übertragen -
        der Dienst sieht nur, was jeder Webserver sieht: deine IP.
    #>
    [CmdletBinding()]
    param([int]$TimeoutSec = 10)

    foreach ($url in @('https://api.ipify.org', 'https://ifconfig.me/ip', 'https://checkip.amazonaws.com', 'https://icanhazip.com')) {
        try {
            $raw = Invoke-RestMethod -Uri $url -TimeoutSec $TimeoutSec -UserAgent $script:PcUserAgent
            $ip = ([string]$raw).Trim()
            if ($ip -match '^(\d{1,3}\.){3}\d{1,3}$') {
                $parsed = $null
                if ([System.Net.IPAddress]::TryParse($ip, [ref]$parsed)) { return $ip }
            }
        } catch { }
    }
    return $null
}

function Get-LocalPrimaryIP {
    <#
    .SYNOPSIS
        Liefert die lokale IP, die für Verbindungen ins Internet benutzt wird.
    .DESCRIPTION
        Ein UDP-"Connect" sendet kein einziges Paket, lässt den Netzwerkstack
        aber die Route wählen. So bekommt man die richtige Adresse auch dann,
        wenn mehrere Adapter (WLAN + LAN + VPN) aktiv sind.
    #>
    [CmdletBinding()]
    param()
    $socket = $null
    try {
        $socket = New-Object System.Net.Sockets.Socket('InterNetwork', 'Dgram', 'Udp')
        $socket.Connect('8.8.8.8', 53)
        return ([System.Net.IPEndPoint]$socket.LocalEndPoint).Address.ToString()
    } catch {
        return $null
    } finally {
        if ($socket) { try { $socket.Dispose() } catch { } }
    }
}

function Test-PrivateIPv4 {
    <#
    .SYNOPSIS
        Prüft, ob eine IPv4 in einem privaten bzw. CGNAT-Bereich liegt.
    #>
    [CmdletBinding()]
    param([string]$IPAddress)

    if (-not $IPAddress) { return $false }
    $o = $IPAddress -split '\.'
    if ($o.Count -ne 4) { return $false }
    $a = [int]$o[0]; $b = [int]$o[1]

    if ($a -eq 10)  { return $true }                              # 10.0.0.0/8
    if ($a -eq 192 -and $b -eq 168) { return $true }              # 192.168.0.0/16
    if ($a -eq 172 -and $b -ge 16 -and $b -le 31) { return $true }# 172.16.0.0/12
    if ($a -eq 127) { return $true }                              # Loopback
    if ($a -eq 169 -and $b -eq 254) { return $true }              # APIPA
    if ($a -eq 100 -and $b -ge 64 -and $b -le 127) { return $true }# 100.64.0.0/10 CGNAT
    return $false
}

function Get-NetworkOverview {
    <#
    .SYNOPSIS
        Sammelt Gateway, lokale Adressen, DNS-Server und aktive Adapter.
    .DESCRIPTION
        Nutzt bevorzugt die Net-Cmdlets. Fehlen die (sehr alte Systeme),
        wird auf .NET-Bordmittel zurückgefallen, damit nie eine leere
        Anzeige entsteht.
    #>
    [CmdletBinding()]
    param()

    $gateway   = $null
    $dns       = @()
    $adapters  = @()
    $addresses = @()

    try {
        $gateway = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
                   Sort-Object RouteMetric |
                   Select-Object -First 1 -ExpandProperty NextHop
    } catch { }

    try {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                       Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
                       Select-Object -ExpandProperty IPAddress)
    } catch { }

    try {
        $dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
                 Where-Object { $_.ServerAddresses.Count -gt 0 } |
                 Select-Object -ExpandProperty ServerAddresses -Unique)
    } catch { }

    # .NET-Fallback: funktioniert immer, auch ohne die Net-Cmdlets.
    try {
        foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($nic.OperationalStatus -ne 'Up') { continue }
            if ($nic.NetworkInterfaceType -eq 'Loopback') { continue }

            $props = $nic.GetIPProperties()
            $nicIPs = @($props.UnicastAddresses |
                        Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } |
                        ForEach-Object { $_.Address.ToString() } |
                        Where-Object { $_ -notlike '169.254.*' })
            if ($nicIPs.Count -eq 0) { continue }

            $adapters += [pscustomobject]@{
                Name        = $nic.Name
                Description = $nic.Description
                Type        = $nic.NetworkInterfaceType.ToString()
                SpeedMbps   = if ($nic.Speed -gt 0) { [math]::Round($nic.Speed / 1MB, 0) } else { 0 }
                MacAddress  = ($nic.GetPhysicalAddress().ToString() -replace '(.{2})(?!$)', '$1:')
                IPv4        = ($nicIPs -join ', ')
            }

            if (-not $gateway) {
                $gw = @($props.GatewayAddresses |
                        Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0' } |
                        Select-Object -First 1)
                if ($gw.Count -gt 0) { $gateway = $gw[0].Address.ToString() }
            }
            if ($dns.Count -eq 0) {
                $dns = @($props.DnsAddresses |
                         Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                         ForEach-Object { $_.ToString() })
            }
            if ($addresses.Count -eq 0) { $addresses += $nicIPs }
        }
    } catch { }

    [pscustomobject]@{
        Gateway   = $gateway
        LocalIPs  = @($addresses | Select-Object -Unique)
        DnsServers= @($dns | Select-Object -Unique)
        Adapters  = @($adapters)
        HostName  = [System.Net.Dns]::GetHostName()
    }
}

# ------------------------------------------------------------------------------
# Region: Port-Spezifikation
# ------------------------------------------------------------------------------

function ConvertFrom-PortSpec {
    <#
    .SYNOPSIS
        Wandelt Eingaben wie "80,443,3074" oder "1-3000" in eine Portliste um.
    .DESCRIPTION
        Erlaubt Einzelports, Bereiche und Mischungen, getrennt durch Komma,
        Semikolon oder Leerzeichen. Ungültige Teile werden nicht verschluckt,
        sondern in .Invalid zurückgemeldet, damit die Oberfläche sie anzeigen
        kann.
    .OUTPUTS
        Objekt mit .Ports (int[], sortiert, dedupliziert) und .Invalid (string[])
    #>
    [CmdletBinding()]
    param([string]$Spec)

    $set     = New-Object 'System.Collections.Generic.SortedSet[int]'
    $invalid = New-Object 'System.Collections.Generic.List[string]'

    if ([string]::IsNullOrWhiteSpace($Spec)) {
        return [pscustomobject]@{ Ports = @(); Invalid = @() }
    }

    foreach ($part in ($Spec -split '[,;\s]+' | Where-Object { $_.Trim() -ne '' })) {
        if ($part -match '^(\d{1,5})\s*-\s*(\d{1,5})$') {
            $from = [int]$Matches[1]
            $to   = [int]$Matches[2]
            if ($from -gt $to) { $tmp = $from; $from = $to; $to = $tmp }
            if ($from -lt 1 -or $to -gt 65535) { $invalid.Add($part); continue }
            for ($i = $from; $i -le $to; $i++) { [void]$set.Add($i) }
        }
        elseif ($part -match '^\d{1,5}$') {
            $port = [int]$part
            if ($port -ge 1 -and $port -le 65535) { [void]$set.Add($port) } else { $invalid.Add($part) }
        }
        else {
            $invalid.Add($part)
        }
    }

    [pscustomobject]@{
        Ports   = @($set)
        Invalid = @($invalid)
    }
}

function ConvertTo-PortSpec {
    <#
    .SYNOPSIS
        Fasst eine Portliste wieder kompakt zusammen ("80, 443, 3074-3076").
    #>
    [CmdletBinding()]
    param([int[]]$Ports)

    if (-not $Ports -or $Ports.Count -eq 0) { return '' }
    $sorted = @($Ports | Sort-Object -Unique)
    $parts  = New-Object 'System.Collections.Generic.List[string]'
    $start  = $sorted[0]
    $prev   = $sorted[0]

    for ($i = 1; $i -le $sorted.Count; $i++) {
        $cur = if ($i -lt $sorted.Count) { $sorted[$i] } else { -1 }
        if ($cur -ne ($prev + 1)) {
            if ($start -eq $prev) { $parts.Add("$start") } else { $parts.Add("$start-$prev") }
            $start = $cur
        }
        $prev = $cur
    }
    return ($parts -join ', ')
}

# ------------------------------------------------------------------------------
# Region: TCP-Port-Test von außen
# ------------------------------------------------------------------------------

function Test-PortExternal {
    <#
    .SYNOPSIS
        Prüft, ob ein TCP-Port von außen aus dem Internet erreichbar ist.
    .DESCRIPTION
        Ablauf in zwei Schritten:
          1. Lokal wird kurz ein TcpListener geöffnet. Ohne den würde selbst
             eine korrekte Portweiterleitung "geschlossen" melden, weil niemand
             die Verbindung annimmt.
          2. Ein externer Dienst verbindet sich von außen auf deine öffentliche
             IP und diesen Port und meldet das Ergebnis zurück.

        DATENSCHUTZ-HINWEIS (ehrlich): Schritt 2 überträgt deine öffentliche
        IP-Adresse und die Portnummer an einen fremden Dienst. Ohne einen Rechner
        außerhalb deines Netzes ist ein solcher Test technisch unmöglich.
    .OUTPUTS
        Objekt mit Port, Status ('Open'|'Closed'|'Unknown'|'Error'), Provider,
        Note, DurationMs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$Port,
        [Parameter(Mandatory = $true)][string]$PublicIP,
        [int]$TimeoutSec = 20,
        [switch]$NoListener
    )

    $sw           = [System.Diagnostics.Stopwatch]::StartNew()
    $listener     = $null
    $listenerNote = ''
    $provider     = ''

    if (-not $NoListener) {
        try {
            $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
            $listener.Start()
        } catch {
            $listenerNote = 'Port lokal belegt - läuft dort schon ein Dienst? Externer Test trotzdem durchgeführt.'
            $listener = $null
        }
    }

    $status = 'Error'
    $detail = ''

    try {
        $resp = Invoke-WebRequest -Uri 'https://ports.yougetsignal.com/check-port.php' `
                    -Method Post `
                    -Body @{ remoteAddress = $PublicIP; portNumber = "$Port" } `
                    -TimeoutSec $TimeoutSec -UseBasicParsing -UserAgent $script:PcUserAgent
        $provider = 'yougetsignal.com'
        $content  = $resp.Content
        if     ($content -match 'is open on')   { $status = 'Open' }
        elseif ($content -match 'is closed on') { $status = 'Closed' }
        else {
            $status = 'Unknown'
            $detail = 'Antwort des Dienstes unklar - vermutlich Rate-Limit.'
        }
    } catch {
        # Fallback. Achtung: canyouseeme.org prüft immer die IP des Aufrufers,
        # nicht die übergebene. Bei VPN/Proxy kann das abweichen.
        try {
            $r2 = Invoke-WebRequest -Uri 'https://canyouseeme.org/' -Method Post `
                      -Body @{ port = "$Port" } -TimeoutSec $TimeoutSec -UseBasicParsing -UserAgent $script:PcUserAgent
            $provider = 'canyouseeme.org'
            if     ($r2.Content -match 'Success:') { $status = 'Open' }
            elseif ($r2.Content -match 'Error:')   { $status = 'Closed' }
            else {
                $status = 'Unknown'
                $detail = 'Antwort des Ausweich-Dienstes unklar.'
            }
        } catch {
            $status   = 'Error'
            $provider = '-'
            $detail   = $_.Exception.Message
        }
    } finally {
        if ($listener) { try { $listener.Stop() } catch { } }
    }

    $sw.Stop()

    [pscustomobject]@{
        Port       = $Port
        Status     = $status
        Provider   = $provider
        Note       = (@($listenerNote, $detail) | Where-Object { $_ }) -join ' '
        DurationMs = [int]$sw.ElapsedMilliseconds
    }
}

# ------------------------------------------------------------------------------
# Region: UPnP / SSDP
# ------------------------------------------------------------------------------

function Get-UpnpDevices {
    <#
    .SYNOPSIS
        Sucht per SSDP-Multicast nach UPnP-fähigen Routern im lokalen Netz.
    .DESCRIPTION
        Findet der Aufruf ein InternetGatewayDevice, kann der Router Ports auf
        Zuruf selbst freigeben - viele Spiele nutzen das. Keine Antwort heißt
        entweder "UPnP aus" oder "Router antwortet nicht auf SSDP".
    .OUTPUTS
        Liste von Objekten mit Address, Server, Location
    #>
    [CmdletBinding()]
    param([int]$TimeoutMs = 3000)

    $devices = New-Object 'System.Collections.Generic.List[object]'
    $seen    = New-Object 'System.Collections.Generic.HashSet[string]'
    $udp     = $null

    # Mehrere Suchbegriffe: manche Router antworten nur auf den allgemeinen
    # rootdevice-Aufruf, nicht auf die Gateway-Kennung.
    $suchbegriffe = @(
        'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
        'urn:schemas-upnp-org:device:InternetGatewayDevice:2',
        'upnp:rootdevice'
    )

    try {
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Client.ReceiveTimeout = 1000

        # An die Adresse binden, über die es ins Internet geht. Ohne das schickt
        # Windows den Multicast bei mehreren Adaptern (LAN + WLAN + VPN) unter
        # Umständen über den falschen - und der Router hört nie davon.
        try {
            $lokal = Get-LocalPrimaryIP
            if ($lokal) {
                $udp.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket,
                                            [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
                $udp.Client.Bind((New-Object System.Net.IPEndPoint(
                    [System.Net.IPAddress]::Parse($lokal), 0)))
            }
        } catch { }

        $encoding = [System.Text.Encoding]::ASCII
        $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse('239.255.255.250'), 1900)

        # SSDP läuft über UDP, Pakete gehen verloren. Deshalb jeden Suchbegriff
        # zweimal senden statt sich auf einen Versuch zu verlassen.
        foreach ($durchgang in 1..2) {
            foreach ($st in $suchbegriffe) {
                $request = $encoding.GetBytes(
                    "M-SEARCH * HTTP/1.1`r`n" +
                    "HOST: 239.255.255.250:1900`r`n" +
                    "MAN: `"ssdp:discover`"`r`n" +
                    "MX: 2`r`n" +
                    "ST: $st`r`n`r`n")
                try { [void]$udp.Send($request, $request.Length, $endpoint) } catch { }
            }
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
            if ($udp.Available -le 0) { Start-Sleep -Milliseconds 80; continue }

            $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $data   = $udp.Receive([ref]$remote)
            $text   = $encoding.GetString($data)

            $server   = ''
            $location = ''
            if ($text -match '(?im)^SERVER:\s*(.+)$')   { $server   = $Matches[1].Trim() }
            if ($text -match '(?im)^LOCATION:\s*(.+)$') { $location = $Matches[1].Trim() }

            $key = $remote.Address.ToString() + '|' + $location
            if ($seen.Add($key)) {
                $devices.Add([pscustomobject]@{
                    Address  = $remote.Address.ToString()
                    Server   = $server
                    Location = $location
                })
            }
        }
    } catch { }
    finally { if ($udp) { try { $udp.Close() } catch { } } }

    # .ToArray() statt @(...) - siehe HINWEIS am Dateianfang zu List[object].
    return $devices.ToArray()
}

function Get-NetworkCategory {
    <#
    .SYNOPSIS
        Ermittelt, ob Windows das aktive Netzwerk als privat oder öffentlich
        einstuft.
    .DESCRIPTION
        Das ist bei UPnP entscheidend: in der Kategorie "Öffentlich" blockt die
        Windows-Firewall die Antworten auf SSDP-Multicast. Die Suche findet dann
        garantiert nichts - egal wie gut der Router UPnP beherrscht. Ohne diese
        Information würde das Werkzeug fälschlich melden, der Router könne kein
        UPnP.
    .OUTPUTS
        Objekt mit Category ('Private'|'Public'|'DomainAuthenticated'|'Unknown'),
        InterfaceAlias, IsPublic
    #>
    [CmdletBinding()]
    param()

    try {
        $profil = @(Get-NetConnectionProfile -ErrorAction Stop |
                    Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' } |
                    Select-Object -First 1)
        if ($profil.Count -eq 0) {
            $profil = @(Get-NetConnectionProfile -ErrorAction Stop | Select-Object -First 1)
        }
        if ($profil.Count -gt 0) {
            $kategorie = [string]$profil[0].NetworkCategory
            return [pscustomobject]@{
                Category       = $kategorie
                InterfaceAlias = [string]$profil[0].InterfaceAlias
                IsPublic       = ($kategorie -eq 'Public')
            }
        }
    } catch { }

    return [pscustomobject]@{ Category = 'Unknown'; InterfaceAlias = ''; IsPublic = $false }
}

# ------------------------------------------------------------------------------
# Region: STUN / NAT-Typ
# ------------------------------------------------------------------------------

function ConvertFrom-StunResponse {
    <#
    .SYNOPSIS
        Zerlegt eine STUN-Binding-Response und liest die gesehene Adresse aus.
    .DESCRIPTION
        Prüft Nachrichtentyp, Magic Cookie und Transaction-ID, damit eine
        verspätete Antwort eines anderen Servers nicht fälschlich einem
        anderen Ziel zugeordnet wird. Unterstützt XOR-MAPPED-ADDRESS (RFC 5389)
        und das ältere MAPPED-ADDRESS (RFC 3489), jeweils IPv4.
    #>
    [CmdletBinding()]
    param([byte[]]$Response, [byte[]]$TransactionId)

    if (-not $Response -or $Response.Length -lt 20) { return $null }
    if ($Response[0] -ne 0x01 -or $Response[1] -ne 0x01) { return $null }          # Binding Response
    if ($Response[4] -ne 0x21 -or $Response[5] -ne 0x12 -or
        $Response[6] -ne 0xA4 -or $Response[7] -ne 0x42) { return $null }          # Magic Cookie
    for ($i = 0; $i -lt 12; $i++) {
        if ($Response[8 + $i] -ne $TransactionId[$i]) { return $null }
    }

    $pos = 20
    while ($pos + 4 -le $Response.Length) {
        $attrType = ([int]$Response[$pos] -shl 8) -bor $Response[$pos + 1]
        $attrLen  = ([int]$Response[$pos + 2] -shl 8) -bor $Response[$pos + 3]
        if ($pos + 4 + $attrLen -gt $Response.Length) { break }

        if ($attrLen -ge 8 -and $Response[$pos + 5] -eq 0x01) {                    # Family = IPv4
            if ($attrType -eq 0x0020) {                                           # XOR-MAPPED-ADDRESS
                $port = (([int]$Response[$pos + 6] -shl 8) -bor $Response[$pos + 7]) -bxor 0x2112
                $ip = '{0}.{1}.{2}.{3}' -f ($Response[$pos + 8]  -bxor 0x21),
                                           ($Response[$pos + 9]  -bxor 0x12),
                                           ($Response[$pos + 10] -bxor 0xA4),
                                           ($Response[$pos + 11] -bxor 0x42)
                return @{ IP = $ip; Port = $port }
            }
            if ($attrType -eq 0x0001) {                                           # MAPPED-ADDRESS
                $port = ([int]$Response[$pos + 6] -shl 8) -bor $Response[$pos + 7]
                $ip = '{0}.{1}.{2}.{3}' -f $Response[$pos + 8], $Response[$pos + 9],
                                           $Response[$pos + 10], $Response[$pos + 11]
                return @{ IP = $ip; Port = $port }
            }
        }

        $pos += 4 + $attrLen
        if (($attrLen % 4) -ne 0) { $pos += (4 - ($attrLen % 4)) }                 # 32-Bit-Padding
    }
    return $null
}

function Get-StunMappings {
    <#
    .SYNOPSIS
        Fragt mehrere STUN-Server über EINEN Socket und sammelt die Antworten.
    .DESCRIPTION
        Der gemeinsame Socket ist entscheidend: nur so ist vergleichbar, ob das
        NAT dieselbe öffentliche Adresse+Port für verschiedene Ziele benutzt.
        Mit je eigenem Socket wären die Ports immer verschieden und das
        Ergebnis wäre wertlos.
    #>
    [CmdletBinding()]
    param(
        [int]$TimeoutMs = 2500,
        [scriptblock]$OnProgress
    )

    $servers = @(
        @{ Name = 'stun.l.google.com';         Port = 19302 },
        @{ Name = 'stun1.l.google.com';        Port = 19302 },
        @{ Name = 'stun.cloudflare.com';       Port = 3478  },
        @{ Name = 'stun.nextcloud.com';        Port = 443   },
        @{ Name = 'stun.sipgate.net';          Port = 3478  }
    )

    $mappings = New-Object 'System.Collections.Generic.List[object]'
    $udp      = $null
    $random   = New-Object System.Random

    try {
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Client.ReceiveTimeout = $TimeoutMs

        foreach ($server in $servers) {
            if ($OnProgress) { & $OnProgress $server.Name }
            try {
                $address = @([System.Net.Dns]::GetHostAddresses($server.Name) |
                             Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                             Select-Object -First 1)
                if ($address.Count -eq 0) { continue }

                $txId = New-Object byte[] 12
                $random.NextBytes($txId)

                $request = New-Object byte[] 20
                $request[0] = 0x00; $request[1] = 0x01                             # Binding Request
                $request[4] = 0x21; $request[5] = 0x12
                $request[6] = 0xA4; $request[7] = 0x42                             # Magic Cookie
                [Array]::Copy($txId, 0, $request, 8, 12)

                $endpoint = New-Object System.Net.IPEndPoint($address[0], $server.Port)
                [void]$udp.Send($request, $request.Length, $endpoint)

                $got = $null
                for ($attempt = 0; $attempt -lt 3 -and -not $got; $attempt++) {
                    try {
                        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                        $data   = $udp.Receive([ref]$remote)
                        $parsed = ConvertFrom-StunResponse -Response $data -TransactionId $txId
                        if ($parsed) {
                            $got = $parsed
                            $mappings.Add([pscustomobject]@{
                                Server  = $server.Name
                                ExtIP   = $parsed.IP
                                ExtPort = $parsed.Port
                            })
                        }
                    } catch {
                        break   # Timeout -> nächster Server
                    }
                }
            } catch { }
        }
    } catch { }
    finally { if ($udp) { try { $udp.Close() } catch { } } }

    # .ToArray() statt @(...) - siehe HINWEIS am Dateianfang zu List[object].
    return $mappings.ToArray()
}

function Get-NatAssessment {
    <#
    .SYNOPSIS
        Bewertet aus den STUN-Ergebnissen das NAT-Verhalten.
    .DESCRIPTION
        EHRLICHE EINORDNUNG, was dieser Test kann und was nicht:

        Messbar ist das MAPPING-Verhalten nach RFC 5780:
          - gleiche externe Adresse+Port für alle Ziele  -> Endpoint-Independent
            Mapping (umgangssprachlich "Cone-NAT")
          - wechselnde Ports je Ziel -> Endpoint-Dependent Mapping ("symmetrisch")

        NICHT messbar ist das FILTERING-Verhalten (wer darf zurückschicken),
        weil dafür ein Server nötig wäre, der von einer zweiten IP antwortet.
        Deshalb steht hier "MODERAT" und nicht pauschal "OFFEN" - die endgültige
        Einstufung im Spiel hängt zusätzlich an der Portfreigabe.
    .OUTPUTS
        Objekt mit Level ('Open'|'Moderate'|'Strict'|'Unknown'), Behaviour,
        Title, Reasons, Mappings, ExternalIP, LocalIP, IsCgnat
    #>
    [CmdletBinding()]
    param(
        [object[]]$Mappings,
        [string]$LocalIP,
        [string]$PublicIP
    )

    $result = [ordered]@{
        Level      = 'Unknown'
        Behaviour  = 'unbekannt'
        Title      = 'Unbekannt'
        Reasons    = @()
        Mappings   = @($Mappings)
        ExternalIP = $null
        LocalIP    = $LocalIP
        IsCgnat    = $false
    }

    if (-not $Mappings -or $Mappings.Count -eq 0) {
        $result.Level     = 'Strict'
        $result.Behaviour = 'keine STUN-Antwort'
        $result.Title     = 'STRIKT'
        $result.Reasons   = @(
            'Kein einziger STUN-Server hat geantwortet.',
            'Ausgehendes UDP wird blockiert - typisch für Firewalls, Sicherheits-Software oder sehr restriktive Router.',
            'Online-Gaming ist so kaum möglich. Prüfe Firewall, Antivirus-Netzwerkschutz und Router-Einstellungen.'
        )
        return [pscustomobject]$result
    }

    $result.ExternalIP = $Mappings[0].ExtIP
    $unique = @($Mappings | Select-Object -Property ExtIP, ExtPort -Unique)
    $result.IsCgnat = (Test-PrivateIPv4 -IPAddress $Mappings[0].ExtIP)

    if ($unique.Count -eq 1 -and $LocalIP -and ($unique[0].ExtIP -eq $LocalIP)) {
        $result.Level     = 'Open'
        $result.Behaviour = 'kein NAT'
        $result.Title     = 'OFFEN'
        $result.Reasons   = @(
            'Dein PC hängt direkt an einer öffentlichen IP - es gibt kein NAT dazwischen.',
            'Das ist der bestmögliche Fall. Erreichbarkeit hängt jetzt nur noch an der Windows-Firewall.'
        )
    }
    elseif ($unique.Count -eq 1) {
        $result.Level     = 'Moderate'
        $result.Behaviour = 'Endpoint-Independent Mapping (Cone-NAT)'
        $result.Title     = 'MODERAT'
        $result.Reasons   = @(
            'Dein Router benutzt für alle Ziele dieselbe öffentliche Adresse und denselben Port.',
            'Das ist gutmütiges NAT - mit Portweiterleitung oder UPnP wird daraus im Spiel "OFFEN".',
            'Prüfe im Reiter Port-Test, ob deine Spiele-Ports wirklich erreichbar sind: offen = NAT offen, geschlossen = NAT moderat.'
        )
    }
    else {
        $result.Level     = 'Strict'
        $result.Behaviour = 'Endpoint-Dependent Mapping (symmetrisches NAT)'
        $result.Title     = 'STRIKT'
        $result.Reasons   = @(
            'Dein Router vergibt je nach Ziel einen anderen öffentlichen Port.',
            'Klassische Portweiterleitung hilft dagegen so gut wie nicht.',
            'Typische Ursachen: CGNAT beim Anbieter, Mobilfunk/LTE, doppeltes NAT durch zwei Router, Firmennetz.',
            'Was hilft: öffentliche IPv4 beim Anbieter anfragen, Router-Kaskade in den Bridge-Modus setzen, UPnP aktivieren.'
        )
    }

    if ($result.IsCgnat) {
        $result.Level   = 'Strict'
        $result.Title   = 'STRIKT'
        $result.Reasons = @(
            "Die von außen gesehene Adresse ($($Mappings[0].ExtIP)) liegt im CGNAT-Bereich 100.64.0.0/10.",
            'Du teilst dir eine öffentliche IP mit anderen Kunden. Portweiterleitung ist damit technisch unmöglich,',
            'egal was du im Router einstellst. Nur der Anbieter kann das ändern (echte IPv4 / DS-Lite abschalten).'
        ) + $result.Reasons
    }

    if ($PublicIP -and $result.ExternalIP -and $PublicIP -ne $result.ExternalIP -and -not $result.IsCgnat) {
        $result.Reasons += "Hinweis: HTTP meldet $PublicIP, STUN meldet $($result.ExternalIP). Das deutet auf VPN, Proxy oder mehrere Internet-Zugänge hin."
    }

    return [pscustomobject]$result
}

# ------------------------------------------------------------------------------
# Region: Export
# ------------------------------------------------------------------------------

function Export-PortCheckResult {
    <#
    .SYNOPSIS
        Schreibt Ergebnisse als CSV, JSON oder Text-Report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Results,
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('csv', 'json', 'txt')][string]$Format = 'csv',
        [string]$PublicIP = ''
    )

    $plain = @($Results | Select-Object Port, Status, Provider, DurationMs, Note)

    switch ($Format) {
        'csv'  { $plain | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 }
        'json' {
            [pscustomobject]@{
                Tool      = 'TEE PortChecker'
                Generated = (Get-Date).ToString('o')
                PublicIP  = $PublicIP
                Results   = $plain
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
        }
        'txt'  {
            $open   = @($plain | Where-Object { $_.Status -eq 'Open' })
            $closed = @($plain | Where-Object { $_.Status -eq 'Closed' })
            $lines  = New-Object 'System.Collections.Generic.List[string]'
            $lines.Add('TEE PortChecker - Ergebnisbericht')
            $lines.Add('Erstellt: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
            $lines.Add('Öffentliche IP: ' + $PublicIP)
            $lines.Add('')
            $lines.Add(('Geprüft: {0}   Offen: {1}   Geschlossen: {2}   Sonstige: {3}' -f
                        $plain.Count, $open.Count, $closed.Count, ($plain.Count - $open.Count - $closed.Count)))
            $lines.Add('')
            if ($open.Count -gt 0)  { $lines.Add('Offene Ports: ' + (ConvertTo-PortSpec -Ports @($open.Port))) }
            $lines.Add('')
            $lines.Add(('{0,-8} {1,-12} {2,-18} {3}' -f 'Port', 'Status', 'Dienst', 'Hinweis'))
            $lines.Add(('-' * 78))
            foreach ($row in $plain) {
                $lines.Add(('{0,-8} {1,-12} {2,-18} {3}' -f $row.Port, $row.Status, $row.Provider, $row.Note))
            }
            Set-Content -Path $Path -Value $lines -Encoding UTF8
        }
    }
    return $Path
}
