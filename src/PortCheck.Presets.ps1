#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - Preset-Datenbank
================================================================================
 Bekannte Portlisten von Spielen, Konsolen und Diensten.

 AUFBAU (wichtig zu verstehen):
   Konsolen haben feste Netzwerk-Ports, die für JEDES Spiel darauf gelten.
   Deshalb gibt es "Plattform-Presets" (ps3, ps4, xbox360 ...) und Spiele
   verweisen über BaseId darauf. Ein Preset "Black Ops II (PS3)" ist also
   PS3-Basisports + evtl. titelspezifische Ports - genau so, wie es der
   Hersteller-Support beschreibt. Das vermeidet Copy-Paste-Fehler und macht
   Korrekturen an einer Stelle wirksam.

 EHRLICHER HINWEIS ZUR GENAUIGKEIT:
   Diese Listen stammen aus den offiziellen Support-Seiten der Hersteller
   (Feld "Source"). Hersteller ändern Ports gelegentlich ohne Ankündigung,
   und ältere Titel mit abgeschalteten Servern sind hier nur noch für
   private/Community-Server sinnvoll. Wenn dir ein Fehler auffällt:
   Pull Request auf diese Datei - sie ist bewusst die einzige Stelle mit
   Portdaten.

   Von außen testbar ist ausschließlich TCP. Die UDP-Spalte ist dennoch
   gepflegt, weil du diese Ports im Router trotzdem freigeben musst - viele
   Spiele nutzen für den eigentlichen Spielverkehr UDP.

 Lizenz: MIT (siehe LICENSE)
================================================================================
#>

function New-PortCheckPreset {
    <#
    .SYNOPSIS
        Interner Helfer - erzeugt einen Preset-Eintrag mit einheitlichen Feldern.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Category,
        [string]$Platform = 'PC',
        [string]$Vendor   = '',
        [int]$Year        = 0,
        [int[]]$TCP       = @(),
        [int[]]$UDP       = @(),
        [string]$BaseId   = '',
        [string]$Note     = '',
        [string]$Source   = ''
    )

    [pscustomobject]@{
        Id       = $Id
        Name     = $Name
        Category = $Category
        Platform = $Platform
        Vendor   = $Vendor
        Year     = $Year
        TCP      = @($TCP)
        UDP      = @($UDP)
        BaseId   = $BaseId
        Note     = $Note
        Source   = $Source
    }
}

function Get-PortCheckPresets {
    <#
    .SYNOPSIS
        Liefert alle Presets als flache Liste.
    .DESCRIPTION
        Die Rohdaten. Für die tatsächlich zu prüfenden Ports bitte
        Resolve-PresetPorts benutzen - das löst BaseId-Verweise auf.
    #>
    [CmdletBinding()]
    param()

    # =========================================================================
    # PLATTFORMEN - Basisports der Konsolen, gelten für alle Spiele darauf
    # =========================================================================
    $sonySrc  = 'https://www.playstation.com/support/console-networking/'
    $msSrc    = 'https://support.xbox.com/help/hardware-network/connect-network/network-ports-used-xbox-live'
    $ninSrc   = 'https://en-americas-support.nintendo.com/app/answers/detail/a_id/22272'

    New-PortCheckPreset -Id 'ps3' -Name 'PlayStation 3 (Basis)' -Category 'Konsolen' -Platform 'PS3' -Vendor 'Sony' -Year 2006 `
        -TCP @(80, 443, 3478, 3479, 3480, 5223) -UDP @(3478, 3479, 3658) `
        -Note 'PSN-Basisports der PS3. Gelten für jedes PS3-Spiel zusätzlich zu titelspezifischen Ports.' -Source $sonySrc

    New-PortCheckPreset -Id 'ps4' -Name 'PlayStation 4 (Basis)' -Category 'Konsolen' -Platform 'PS4' -Vendor 'Sony' -Year 2013 `
        -TCP @(80, 443, 1935, 3478, 3479, 3480) -UDP @(3478, 3479) `
        -Note 'PSN-Basisports der PS4. 1935 wird für Streaming/Übertragung genutzt.' -Source $sonySrc

    New-PortCheckPreset -Id 'ps5' -Name 'PlayStation 5 (Basis)' -Category 'Konsolen' -Platform 'PS5' -Vendor 'Sony' -Year 2020 `
        -TCP @(80, 443, 1935, 3478, 3479, 3480) -UDP @(3478, 3479) `
        -Note 'PSN-Basisports der PS5 - identisch zur PS4.' -Source $sonySrc

    New-PortCheckPreset -Id 'psvita' -Name 'PS Vita / PSP' -Category 'Konsolen' -Platform 'Vita' -Vendor 'Sony' -Year 2011 `
        -TCP @(80, 443, 5223) -UDP @(3478, 3479, 3658) `
        -Note 'Handheld-PSN. Offizielle Server weitgehend abgeschaltet.' -Source $sonySrc

    New-PortCheckPreset -Id 'xbox360' -Name 'Xbox 360 (Basis)' -Category 'Konsolen' -Platform 'Xbox 360' -Vendor 'Microsoft' -Year 2005 `
        -TCP @(80, 443, 3074) -UDP @(88, 3074) `
        -Note 'Xbox-Live-Basisports der 360. UDP 88 ist Kerberos-Authentifizierung.' -Source $msSrc

    New-PortCheckPreset -Id 'xboxone' -Name 'Xbox One (Basis)' -Category 'Konsolen' -Platform 'Xbox One' -Vendor 'Microsoft' -Year 2013 `
        -TCP @(53, 80, 3074) -UDP @(53, 88, 500, 3074, 3544, 4500) `
        -Note 'UDP 3544/4500/500 gehören zu Teredo - ohne die bleibt der NAT-Typ strikt.' -Source $msSrc

    New-PortCheckPreset -Id 'xboxseries' -Name 'Xbox Series X|S (Basis)' -Category 'Konsolen' -Platform 'Xbox Series' -Vendor 'Microsoft' -Year 2020 `
        -TCP @(53, 80, 3074) -UDP @(53, 88, 500, 3074, 3544, 4500) `
        -Note 'Identisch zur Xbox One.' -Source $msSrc

    New-PortCheckPreset -Id 'switch' -Name 'Nintendo Switch (Basis)' -Category 'Konsolen' -Platform 'Switch' -Vendor 'Nintendo' -Year 2017 `
        -TCP @(80, 443, 6667, 12400, 28910, 29900, 29901, 29920) -UDP @(45000, 45001, 45002, 45003, 45004, 45005) `
        -Note 'Nintendo empfiehlt offiziell UDP 1-65535 freizugeben; hier ist der praktisch genutzte Bereich hinterlegt.' -Source $ninSrc

    New-PortCheckPreset -Id 'wiiu' -Name 'Wii U (Basis)' -Category 'Konsolen' -Platform 'Wii U' -Vendor 'Nintendo' -Year 2012 `
        -TCP @(80, 443, 6667, 12400, 28910, 29900, 29901, 29920) -UDP @(45000, 45001, 45002, 45003, 45004, 45005) `
        -Note 'Offizielle Server abgeschaltet - relevant nur noch für Ersatznetzwerke wie Pretendo.' -Source $ninSrc

    New-PortCheckPreset -Id 'steamdeck' -Name 'Steam Deck / Steam-Client' -Category 'Konsolen' -Platform 'Steam' -Vendor 'Valve' -Year 2022 `
        -TCP @(27015, 27016, 27017, 27018, 27019, 27020, 27036, 27037) -UDP @(3478, 4379, 4380, 27000, 27015, 27031, 27036) `
        -Note 'Steam-Client, Remote Play und Downloads.' -Source 'https://help.steampowered.com/de/faqs/view/669D-4CFA-B012-4D1E'

    # =========================================================================
    # CALL OF DUTY - komplette Reihe mit Plattform-Varianten
    # =========================================================================
    $codSrc = 'https://support.activision.com/articles/ports-used-for-call-of-duty-games'

    # --- Black Ops (2010) ---
    New-PortCheckPreset -Id 'bo1-pc' -Name 'Black Ops (PC)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Treyarch' -Year 2010 `
        -TCP @(3074, 27014, 27015, 27016, 27017, 27018, 27019, 27020, 27030, 27039, 28960) `
        -UDP @(3074, 3075, 27000, 27015, 27031, 27036, 28960) `
        -Note 'Steam-Version. 28960 ist der klassische CoD-Spielport, 3075 kommt bei Party/Lobby dazu.' -Source $codSrc

    New-PortCheckPreset -Id 'bo1-ps3' -Name 'Black Ops (PS3)' -Category 'Call of Duty' -Platform 'PS3' -Vendor 'Treyarch' -Year 2010 `
        -BaseId 'ps3' -TCP @(3074) -UDP @(3074, 3075) `
        -Note 'PSN-Basisports plus CoD-Spielport. Offizielle Server laufen über Community-Ersatz.' -Source $codSrc

    New-PortCheckPreset -Id 'bo1-x360' -Name 'Black Ops (Xbox 360)' -Category 'Call of Duty' -Platform 'Xbox 360' -Vendor 'Treyarch' -Year 2010 `
        -BaseId 'xbox360' -TCP @(3074) -UDP @(3074, 3075) `
        -Note 'Xbox-Live-Basisports plus CoD-Spielport.' -Source $codSrc

    # --- Black Ops II (2012) ---
    New-PortCheckPreset -Id 'bo2-pc' -Name 'Black Ops II (PC)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Treyarch' -Year 2012 `
        -TCP @(3074, 27014, 27015, 27016, 27017, 27018, 27019, 27020, 27030, 27039) `
        -UDP @(3074, 3075, 4379, 4380, 27000, 27015, 27031, 27036, 28960) `
        -Note 'Steam-Version. Für eigene Server/Lobbys ist UDP 4976-4977 zusätzlich verbreitet.' -Source $codSrc

    New-PortCheckPreset -Id 'bo2-ps3' -Name 'Black Ops II (PS3)' -Category 'Call of Duty' -Platform 'PS3' -Vendor 'Treyarch' -Year 2012 `
        -BaseId 'ps3' -TCP @(3074) -UDP @(3074, 3075) `
        -Note 'PSN-Basisports plus CoD-Spielport. Die PS3-Fassung ist bis heute die aktivste Community-Version.' -Source $codSrc

    New-PortCheckPreset -Id 'bo2-x360' -Name 'Black Ops II (Xbox 360)' -Category 'Call of Duty' -Platform 'Xbox 360' -Vendor 'Treyarch' -Year 2012 `
        -BaseId 'xbox360' -TCP @(3074) -UDP @(3074, 3075) `
        -Note 'Xbox-Live-Basisports plus CoD-Spielport.' -Source $codSrc

    New-PortCheckPreset -Id 'bo2-wiiu' -Name 'Black Ops II (Wii U)' -Category 'Call of Duty' -Platform 'Wii U' -Vendor 'Treyarch' -Year 2012 `
        -BaseId 'wiiu' -TCP @(3074) -UDP @(3074, 3075) `
        -Note 'Nintendo-Netzwerkdienst für Wii U ist eingestellt.' -Source $codSrc

    # --- Black Ops III (2015) ---
    New-PortCheckPreset -Id 'bo3-pc' -Name 'Black Ops III (PC)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Treyarch' -Year 2015 `
        -TCP @(3074, 27014, 27015, 27016, 27017, 27018, 27019, 27020, 27030, 27039) `
        -UDP @(3074, 3478, 4379, 4380, 27000, 27015, 27031, 27036) `
        -Note 'Steam-Version.' -Source $codSrc

    New-PortCheckPreset -Id 'bo3-ps4' -Name 'Black Ops III (PS4)' -Category 'Call of Duty' -Platform 'PS4' -Vendor 'Treyarch' -Year 2015 `
        -BaseId 'ps4' -TCP @(3074) -UDP @(3074) -Source $codSrc

    New-PortCheckPreset -Id 'bo3-ps3' -Name 'Black Ops III (PS3)' -Category 'Call of Duty' -Platform 'PS3' -Vendor 'Treyarch' -Year 2015 `
        -BaseId 'ps3' -TCP @(3074) -UDP @(3074) `
        -Note 'Abgespeckte Last-Gen-Fassung ohne Kampagne.' -Source $codSrc

    New-PortCheckPreset -Id 'bo3-xb1' -Name 'Black Ops III (Xbox One)' -Category 'Call of Duty' -Platform 'Xbox One' -Vendor 'Treyarch' -Year 2015 `
        -BaseId 'xboxone' -TCP @(3074) -UDP @(3074) -Source $codSrc

    New-PortCheckPreset -Id 'bo3-x360' -Name 'Black Ops III (Xbox 360)' -Category 'Call of Duty' -Platform 'Xbox 360' -Vendor 'Treyarch' -Year 2015 `
        -BaseId 'xbox360' -TCP @(3074) -UDP @(3074) -Source $codSrc

    # --- Weitere CoD-Titel ---
    New-PortCheckPreset -Id 'bo4' -Name 'Black Ops 4 (PC)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Treyarch' -Year 2018 `
        -TCP @(80, 443, 1119, 3074, 3724, 6113) -UDP @(3074, 3478, 3479, 5060, 5062, 6250) `
        -Note 'Battle.net-Titel - nutzt die Blizzard-Ports.' -Source $codSrc

    New-PortCheckPreset -Id 'bocw' -Name 'Black Ops Cold War' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Treyarch' -Year 2020 `
        -TCP @(80, 443, 3074, 27014, 27015, 27030) -UDP @(3074, 3478, 4379, 4380, 27000, 27031) -Source $codSrc

    New-PortCheckPreset -Id 'bo6' -Name 'Black Ops 6' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Treyarch' -Year 2024 `
        -TCP @(80, 443, 3074, 27014, 27015, 27030) -UDP @(3074, 3478, 4379, 4380, 27000, 27031) -Source $codSrc

    New-PortCheckPreset -Id 'mw2-old' -Name 'Modern Warfare 2 (2009)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Infinity Ward' -Year 2009 `
        -TCP @(3074, 27014, 27015, 27016, 27017, 27018, 27019, 27020, 27030, 28960) `
        -UDP @(3074, 27000, 27015, 27031, 28960) -Source $codSrc

    New-PortCheckPreset -Id 'mw3-old' -Name 'Modern Warfare 3 (2011)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Infinity Ward' -Year 2011 `
        -TCP @(3074, 27014, 27015, 27016, 27017, 27018, 27019, 27020, 27030, 28960) `
        -UDP @(3074, 27000, 27015, 27031, 28960) -Source $codSrc

    New-PortCheckPreset -Id 'ghosts' -Name 'Call of Duty: Ghosts' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Infinity Ward' -Year 2013 `
        -TCP @(3074, 27014, 27015, 27030) -UDP @(3074, 27000, 27015, 27031) -Source $codSrc

    New-PortCheckPreset -Id 'aw' -Name 'Advanced Warfare' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Sledgehammer' -Year 2014 `
        -TCP @(3074, 27014, 27015, 27030) -UDP @(3074, 27000, 27015, 27031) -Source $codSrc

    New-PortCheckPreset -Id 'ww2' -Name 'Call of Duty: WWII' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Sledgehammer' -Year 2017 `
        -TCP @(3074, 27014, 27015, 27030) -UDP @(3074, 3478, 4379, 4380, 27000, 27031) -Source $codSrc

    New-PortCheckPreset -Id 'mw2019' -Name 'Modern Warfare (2019)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Infinity Ward' -Year 2019 `
        -TCP @(80, 443, 3074, 27014, 27015, 27030) -UDP @(3074, 3478, 4379, 4380, 27000, 27031) -Source $codSrc

    New-PortCheckPreset -Id 'warzone' -Name 'Warzone' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Activision' -Year 2020 `
        -TCP @(80, 443, 3074, 27014, 27015, 27030) -UDP @(3074, 3478, 4379, 4380, 27000, 27031) `
        -Note 'Gleiche Ports wie der jeweils aktuelle CoD-Hauptteil.' -Source $codSrc

    New-PortCheckPreset -Id 'mw2-2022' -Name 'Modern Warfare II (2022)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Infinity Ward' -Year 2022 `
        -TCP @(80, 443, 3074, 27014, 27015, 27030) -UDP @(3074, 3478, 4379, 4380, 27000, 27031) -Source $codSrc

    New-PortCheckPreset -Id 'mw3-2023' -Name 'Modern Warfare III (2023)' -Category 'Call of Duty' -Platform 'PC' -Vendor 'Sledgehammer' -Year 2023 `
        -TCP @(80, 443, 3074, 27014, 27015, 27030) -UDP @(3074, 3478, 4379, 4380, 27000, 27031) -Source $codSrc

    # =========================================================================
    # SHOOTER
    # =========================================================================
    New-PortCheckPreset -Id 'cs2' -Name 'Counter-Strike 2 / CS:GO' -Category 'Shooter' -Platform 'PC' -Vendor 'Valve' -Year 2023 `
        -TCP @(27015, 27016, 27017, 27018, 27019, 27020, 27036, 27037) `
        -UDP @(3478, 4379, 4380, 27000, 27015, 27031, 27036) `
        -Source 'https://help.steampowered.com/de/faqs/view/669D-4CFA-B012-4D1E'

    New-PortCheckPreset -Id 'valorant' -Name 'Valorant' -Category 'Shooter' -Platform 'PC' -Vendor 'Riot' -Year 2020 `
        -TCP @(2099, 5222, 5223, 5229, 8393, 8394, 8395, 8396, 8397, 8398, 8399, 8400) `
        -UDP @(7000, 7001, 7002, 7003, 7004, 7005, 8000, 8001, 8180, 8181) `
        -Source 'https://support-valorant.riotgames.com/hc/de/articles/360044648213'

    New-PortCheckPreset -Id 'r6' -Name 'Rainbow Six Siege' -Category 'Shooter' -Platform 'PC' -Vendor 'Ubisoft' -Year 2015 `
        -TCP @(80, 443, 13000, 13005, 13200, 14000, 14001, 14008, 14020, 14021, 14022, 14023, 14024) `
        -UDP @(3074, 6015, 10000, 10001, 10002, 10003) `
        -Source 'https://www.ubisoft.com/de-de/help/article/000063138'

    New-PortCheckPreset -Id 'bf2042' -Name 'Battlefield 2042 / V / 1' -Category 'Shooter' -Platform 'PC' -Vendor 'EA DICE' -Year 2021 `
        -TCP @(80, 443, 9988, 17502, 20000, 20001, 20002, 22990, 42127) `
        -UDP @(3659, 14000, 22990, 25200, 25300) `
        -Source 'https://help.ea.com/de/help/faq/ports-to-connect-to-ea-games/'

    New-PortCheckPreset -Id 'apex' -Name 'Apex Legends' -Category 'Battle Royale' -Platform 'PC' -Vendor 'Respawn' -Year 2019 `
        -TCP @(80, 443, 1024, 1124, 3216, 9960, 9969, 18000, 18060, 18120, 27900, 28910, 29900) `
        -UDP @(1024, 1124, 3659, 9000, 9999, 18000, 29900) `
        -Source 'https://help.ea.com/de/help/apex-legends/apex-legends/'

    New-PortCheckPreset -Id 'titanfall2' -Name 'Titanfall 2' -Category 'Shooter' -Platform 'PC' -Vendor 'Respawn' -Year 2016 `
        -TCP @(80, 443, 9960, 9969, 18000) -UDP @(3659, 9000, 9999, 18000) `
        -Source 'https://help.ea.com/de/help/faq/ports-to-connect-to-ea-games/'

    New-PortCheckPreset -Id 'overwatch' -Name 'Overwatch 2' -Category 'Shooter' -Platform 'PC' -Vendor 'Blizzard' -Year 2022 `
        -TCP @(80, 443, 1119, 1120, 3724, 6113) -UDP @(3478, 3479, 5060, 5062, 6250, 12000, 29900) `
        -Source 'https://eu.battle.net/support/de/article/000068259'

    New-PortCheckPreset -Id 'halo' -Name 'Halo Infinite / MCC' -Category 'Shooter' -Platform 'PC' -Vendor '343 Industries' -Year 2021 `
        -TCP @(80, 443, 3074) -UDP @(88, 500, 3074, 3544, 4500) `
        -Note 'Nutzt die Xbox-Live-Infrastruktur, auch auf dem PC.' -Source $msSrc

    New-PortCheckPreset -Id 'tarkov' -Name 'Escape from Tarkov' -Category 'Shooter' -Platform 'PC' -Vendor 'Battlestate' -Year 2017 `
        -TCP @(80, 443, 6969) -UDP @(17000, 17001, 17002, 17003, 17004, 17005) `
        -Source 'https://support.escapefromtarkov.com/'

    New-PortCheckPreset -Id 'tf2' -Name 'Team Fortress 2' -Category 'Shooter' -Platform 'PC' -Vendor 'Valve' -Year 2007 `
        -TCP @(27015, 27016, 27020, 27036, 27037) -UDP @(27000, 27015, 27020, 27031, 27036) `
        -Source 'https://help.steampowered.com/de/faqs/view/669D-4CFA-B012-4D1E'

    # =========================================================================
    # BATTLE ROYALE
    # =========================================================================
    New-PortCheckPreset -Id 'fortnite' -Name 'Fortnite' -Category 'Battle Royale' -Platform 'PC' -Vendor 'Epic' -Year 2017 `
        -TCP @(80, 443, 5222, 5223, 5795, 5847, 5222) -UDP @(3478, 3479, 5060, 5062, 5222, 6250, 9000, 9001) `
        -Source 'https://www.epicgames.com/help/de/'

    New-PortCheckPreset -Id 'pubg' -Name 'PUBG: Battlegrounds' -Category 'Battle Royale' -Platform 'PC' -Vendor 'Krafton' -Year 2017 `
        -TCP @(80, 443, 27015, 27016, 27017, 27018, 27019, 27020, 27036) `
        -UDP @(7086, 7087, 7088, 7089, 7090, 7091, 7092, 7093, 27000, 27015, 27031) `
        -Source 'https://support.pubg.com/'

    New-PortCheckPreset -Id 'fallguys' -Name 'Fall Guys' -Category 'Battle Royale' -Platform 'PC' -Vendor 'Mediatonic' -Year 2020 `
        -TCP @(80, 443, 5222, 5795, 5847) -UDP @(3478, 3479, 5060, 5062, 6250) `
        -Source 'https://www.epicgames.com/help/de/'

    # =========================================================================
    # SURVIVAL & SANDBOX
    # =========================================================================
    New-PortCheckPreset -Id 'mc-java' -Name 'Minecraft Java (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Mojang' -Year 2011 `
        -TCP @(25565) -UDP @(25565) `
        -Note 'Standard-Serverport. Für einen eigenen Server MUSS TCP 25565 offen sein - dieser Test zeigt das direkt.' `
        -Source 'https://help.minecraft.net/hc/de/articles/24135718760845'

    New-PortCheckPreset -Id 'mc-bedrock' -Name 'Minecraft Bedrock (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Mojang' -Year 2016 `
        -TCP @(19132, 19133) -UDP @(19132, 19133) `
        -Note 'Bedrock läuft über UDP - der TCP-Test ist hier nur eine Zusatzinfo.' `
        -Source 'https://help.minecraft.net/hc/de/articles/24135718760845'

    New-PortCheckPreset -Id 'ark' -Name 'ARK: Survival (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Studio Wildcard' -Year 2017 `
        -TCP @(27015, 27020) -UDP @(7777, 7778, 27015) `
        -Source 'https://survivetheark.com/'

    New-PortCheckPreset -Id 'rust' -Name 'Rust (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Facepunch' -Year 2018 `
        -TCP @(28016, 28082) -UDP @(28015, 28016) `
        -Source 'https://wiki.facepunch.com/rust/'

    New-PortCheckPreset -Id 'valheim' -Name 'Valheim (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Iron Gate' -Year 2021 `
        -TCP @(2456, 2457, 2458) -UDP @(2456, 2457, 2458) `
        -Source 'https://valheim.fandom.com/wiki/Dedicated_servers'

    New-PortCheckPreset -Id 'palworld' -Name 'Palworld (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Pocketpair' -Year 2024 `
        -TCP @(8211, 27015) -UDP @(8211, 27015) `
        -Source 'https://tech.palworldgame.com/'

    New-PortCheckPreset -Id 'terraria' -Name 'Terraria (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Re-Logic' -Year 2011 `
        -TCP @(7777) -UDP @(7777) `
        -Source 'https://terraria.fandom.com/wiki/Server'

    New-PortCheckPreset -Id 'dayz' -Name 'DayZ (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Bohemia' -Year 2018 `
        -TCP @(2302, 2303, 2304, 2305, 27016) -UDP @(2302, 2303, 2304, 2305, 27016) `
        -Source 'https://community.bistudio.com/wiki/DayZ:Server_Configuration'

    New-PortCheckPreset -Id 'satisfactory' -Name 'Satisfactory (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Coffee Stain' -Year 2019 `
        -TCP @(7777) -UDP @(7777) `
        -Source 'https://satisfactory.fandom.com/wiki/Dedicated_servers'

    New-PortCheckPreset -Id 'sevendays' -Name '7 Days to Die (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Fun Pimps' -Year 2013 `
        -TCP @(26900, 8080, 8081) -UDP @(26900, 26901, 26902, 26903) `
        -Source 'https://7daystodie.fandom.com/wiki/Server'

    New-PortCheckPreset -Id 'projectzomboid' -Name 'Project Zomboid (Server)' -Category 'Survival & Sandbox' -Platform 'PC' -Vendor 'Indie Stone' -Year 2013 `
        -TCP @(16261, 16262) -UDP @(16261, 16262) `
        -Source 'https://pzwiki.net/wiki/Dedicated_Server'

    # =========================================================================
    # RENNEN & SPORT
    # =========================================================================
    New-PortCheckPreset -Id 'rocketleague' -Name 'Rocket League' -Category 'Rennen & Sport' -Platform 'PC' -Vendor 'Psyonix' -Year 2015 `
        -TCP @(80, 443, 7000, 7001, 7002, 7003, 7004, 7005, 7006, 7007, 7008, 7009, 8000) `
        -UDP @(7000, 7001, 7002, 7003, 7004, 7005, 7006, 7007, 7008, 7009, 8000) `
        -Source 'https://www.epicgames.com/help/de/'

    New-PortCheckPreset -Id 'eafc' -Name 'EA SPORTS FC / FIFA' -Category 'Rennen & Sport' -Platform 'PC' -Vendor 'EA' -Year 2023 `
        -TCP @(80, 443, 9988, 17502, 20000, 20001, 20002, 42127) -UDP @(3659, 25200, 25211, 25300) `
        -Source 'https://help.ea.com/de/help/faq/ports-to-connect-to-ea-games/'

    New-PortCheckPreset -Id 'forza' -Name 'Forza Horizon / Motorsport' -Category 'Rennen & Sport' -Platform 'PC' -Vendor 'Turn 10' -Year 2021 `
        -TCP @(80, 443, 3074) -UDP @(88, 500, 3074, 3544, 4500) `
        -Note 'Xbox-Live-Infrastruktur.' -Source $msSrc

    New-PortCheckPreset -Id 'gtao' -Name 'GTA Online' -Category 'Rennen & Sport' -Platform 'PC' -Vendor 'Rockstar' -Year 2013 `
        -TCP @(80, 443, 6672) -UDP @(6672, 61455, 61456, 61457, 61458) `
        -Source 'https://support.rockstargames.com/articles/200426246'

    New-PortCheckPreset -Id 'rdr2' -Name 'Red Dead Online' -Category 'Rennen & Sport' -Platform 'PC' -Vendor 'Rockstar' -Year 2018 `
        -TCP @(80, 443, 6672) -UDP @(6672, 61455, 61456, 61457, 61458) `
        -Source 'https://support.rockstargames.com/articles/200426246'

    # =========================================================================
    # MMO & RPG
    # =========================================================================
    New-PortCheckPreset -Id 'wow' -Name 'World of Warcraft' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Blizzard' -Year 2004 `
        -TCP @(80, 443, 1119, 1120, 3724, 6012, 6113) -UDP @(3478, 3479, 6250) `
        -Source 'https://eu.battle.net/support/de/article/000068259'

    New-PortCheckPreset -Id 'diablo' -Name 'Diablo IV / III' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Blizzard' -Year 2023 `
        -TCP @(80, 443, 1119, 1120, 3724, 6113) -UDP @(1119, 6120) `
        -Source 'https://eu.battle.net/support/de/article/000068259'

    New-PortCheckPreset -Id 'destiny2' -Name 'Destiny 2' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Bungie' -Year 2017 `
        -TCP @(80, 443, 1119, 1120, 3074, 3724, 4000, 6113) -UDP @(3074, 3097, 3098, 3099, 3100, 3101, 3102, 3103, 3104, 3105, 3106, 3107) `
        -Source 'https://help.bungie.net/hc/de/articles/360049496531'

    New-PortCheckPreset -Id 'lol' -Name 'League of Legends' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Riot' -Year 2009 `
        -TCP @(80, 443, 2099, 5222, 5223, 8393, 8394, 8395, 8396, 8397, 8398, 8399, 8400) `
        -UDP @(5000, 5001, 5002, 5003, 5004, 5005, 5006, 5007, 5008, 5009, 5010) `
        -Source 'https://support-leagueoflegends.riotgames.com/'

    New-PortCheckPreset -Id 'dota2' -Name 'Dota 2' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Valve' -Year 2013 `
        -TCP @(27015, 27016, 27017, 27018, 27019, 27020, 27036) -UDP @(27000, 27015, 27031, 27036) `
        -Source 'https://help.steampowered.com/de/faqs/view/669D-4CFA-B012-4D1E'

    New-PortCheckPreset -Id 'ffxiv' -Name 'Final Fantasy XIV' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Square Enix' -Year 2013 `
        -TCP @(80, 443, 54992, 54993, 54994, 54995, 55006, 55007, 55021, 55022, 55023, 55024) -UDP @() `
        -Source 'https://eu.finalfantasyxiv.com/lodestone/help/'

    New-PortCheckPreset -Id 'warframe' -Name 'Warframe' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Digital Extremes' -Year 2013 `
        -TCP @(80, 443) -UDP @(4950, 4955, 4960, 4965, 3074, 3080) `
        -Source 'https://digitalextremes.zendesk.com/hc/en-us'

    New-PortCheckPreset -Id 'eldenring' -Name 'Elden Ring / Dark Souls' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'FromSoftware' -Year 2022 `
        -TCP @(27015, 27016, 27036) -UDP @(27000, 27015, 27031, 27036) `
        -Note 'Nutzt Steam-Netzwerk. Bei strengem NAT scheitert das Einladen von Mitspielern.' `
        -Source 'https://help.steampowered.com/de/faqs/view/669D-4CFA-B012-4D1E'

    New-PortCheckPreset -Id 'roblox' -Name 'Roblox' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Roblox' -Year 2006 `
        -TCP @(80, 443) -UDP @(49152, 49153, 49154, 49155, 49156, 49157) `
        -Source 'https://en.help.roblox.com/hc/de/articles/203312880'

    New-PortCheckPreset -Id 'seaofthieves' -Name 'Sea of Thieves' -Category 'MMO & RPG' -Platform 'PC' -Vendor 'Rare' -Year 2018 `
        -TCP @(80, 443, 3074) -UDP @(88, 500, 3074, 3544, 4500, 30000, 30001, 30002) `
        -Note 'Xbox-Live-Infrastruktur.' -Source $msSrc

    # =========================================================================
    # PLATTFORMEN & LAUNCHER
    # =========================================================================
    New-PortCheckPreset -Id 'battlenet' -Name 'Battle.net (Launcher)' -Category 'Plattformen & Launcher' -Platform 'PC' -Vendor 'Blizzard' -Year 2009 `
        -TCP @(80, 443, 1119, 1120, 3724, 6113) -UDP @(1119, 3478, 3479, 5060, 5062, 6250) `
        -Source 'https://eu.battle.net/support/de/article/000068259'

    New-PortCheckPreset -Id 'epic' -Name 'Epic Games Launcher' -Category 'Plattformen & Launcher' -Platform 'PC' -Vendor 'Epic' -Year 2018 `
        -TCP @(80, 443, 5222, 5795, 5847) -UDP @(3478, 3479, 5060, 5062, 6250) `
        -Source 'https://www.epicgames.com/help/de/'

    New-PortCheckPreset -Id 'origin' -Name 'EA App / Origin' -Category 'Plattformen & Launcher' -Platform 'PC' -Vendor 'EA' -Year 2011 `
        -TCP @(80, 443, 3216, 9960, 9969, 18000, 18060, 18120, 27900, 28910, 29900) -UDP @(3659, 9000, 9999, 18000) `
        -Source 'https://help.ea.com/de/help/faq/ports-to-connect-to-ea-games/'

    New-PortCheckPreset -Id 'ubisoft' -Name 'Ubisoft Connect' -Category 'Plattformen & Launcher' -Platform 'PC' -Vendor 'Ubisoft' -Year 2009 `
        -TCP @(80, 443, 13000, 13005, 13200, 14000, 14001, 14008) -UDP @(3074, 3075) `
        -Source 'https://www.ubisoft.com/de-de/help/article/000063138'

    # =========================================================================
    # VOICE & CHAT
    # =========================================================================
    New-PortCheckPreset -Id 'discord' -Name 'Discord (Sprachchat)' -Category 'Voice & Chat' -Platform 'PC' -Vendor 'Discord' -Year 2015 `
        -TCP @(80, 443) -UDP @(50000, 50001, 50002, 50003, 50004, 50005, 50006, 50007, 50008, 50009, 50010) `
        -Note 'Discord braucht ausgehend UDP 50000-65535. Reine TCP-Prüfung sagt hier wenig aus.' `
        -Source 'https://support.discord.com/hc/de/articles/381134546012'

    New-PortCheckPreset -Id 'teamspeak' -Name 'TeamSpeak 3 (Server)' -Category 'Voice & Chat' -Platform 'PC' -Vendor 'TeamSpeak' -Year 2009 `
        -TCP @(30033, 10011, 41144) -UDP @(9987) `
        -Note 'TCP 30033 ist Dateiübertragung, TCP 10011 die Server-Query, UDP 9987 die Sprache.' `
        -Source 'https://support.teamspeak.com/'

    New-PortCheckPreset -Id 'mumble' -Name 'Mumble (Server)' -Category 'Voice & Chat' -Platform 'PC' -Vendor 'Mumble' -Year 2005 `
        -TCP @(64738) -UDP @(64738) -Source 'https://wiki.mumble.info/'

    # =========================================================================
    # SERVER & SONSTIGES
    # =========================================================================
    New-PortCheckPreset -Id 'web' -Name 'Web & Fernwartung' -Category 'Server & Sonstiges' -Platform 'PC' -Vendor 'Standard' -Year 0 `
        -TCP @(21, 22, 23, 25, 53, 80, 110, 143, 443, 465, 587, 993, 995, 3389, 8080, 8443) -UDP @(53) `
        -Note 'Klassische Dienste. ACHTUNG: 3389 (Remotedesktop) oder 23 (Telnet) offen im Internet ist ein ernstes Sicherheitsrisiko.'

    New-PortCheckPreset -Id 'selfhost' -Name 'Selfhosting (Plex, NAS, VPN)' -Category 'Server & Sonstiges' -Platform 'PC' -Vendor 'Standard' -Year 0 `
        -TCP @(32400, 5000, 5001, 8096, 8920, 9091, 51413) -UDP @(1194, 51820, 51413) `
        -Note '32400 Plex, 8096/8920 Jellyfin, 51413 Transmission, UDP 1194 OpenVPN, UDP 51820 WireGuard.'

    New-PortCheckPreset -Id 'common-low' -Name 'Häufige Ports 1-1024' -Category 'Server & Sonstiges' -Platform 'PC' -Vendor 'Standard' -Year 0 `
        -TCP @(20, 21, 22, 23, 25, 53, 67, 68, 69, 80, 110, 123, 135, 137, 138, 139, 143, 161, 389, 443, 445, 465, 514, 587, 636, 993, 995) -UDP @() `
        -Note 'Übersicht der wichtigsten Systemports. Offene 135/137-139/445 nach außen sind ein ernstes Risiko (Windows-Freigaben).'
}

function Resolve-PresetPorts {
    <#
    .SYNOPSIS
        Löst ein Preset inklusive BaseId-Verweis in die endgültigen Portlisten auf.
    .DESCRIPTION
        Ein Konsolen-Spiel erbt die Basisports seiner Plattform. Diese Funktion
        führt beide Listen zusammen, sortiert und entfernt Doppelte.
    .OUTPUTS
        Objekt mit TCP (int[]), UDP (int[]), BaseName (string oder $null)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Preset,
        [object[]]$AllPresets
    )

    if (-not $AllPresets) { $AllPresets = @(Get-PortCheckPresets) }

    $tcp      = New-Object 'System.Collections.Generic.SortedSet[int]'
    $udp      = New-Object 'System.Collections.Generic.SortedSet[int]'
    $baseName = $null

    if ($Preset.BaseId) {
        $base = @($AllPresets | Where-Object { $_.Id -eq $Preset.BaseId })
        if ($base.Count -gt 0) {
            $baseName = $base[0].Name
            foreach ($p in $base[0].TCP) { [void]$tcp.Add($p) }
            foreach ($p in $base[0].UDP) { [void]$udp.Add($p) }
        }
    }

    foreach ($p in $Preset.TCP) { [void]$tcp.Add($p) }
    foreach ($p in $Preset.UDP) { [void]$udp.Add($p) }

    [pscustomobject]@{
        TCP      = @($tcp)
        UDP      = @($udp)
        BaseName = $baseName
    }
}

function Get-PresetCategories {
    <#
    .SYNOPSIS
        Kategorien in fester Anzeigereihenfolge.
    #>
    [CmdletBinding()]
    param()
    @(
        'Konsolen',
        'Call of Duty',
        'Shooter',
        'Battle Royale',
        'Survival & Sandbox',
        'Rennen & Sport',
        'MMO & RPG',
        'Plattformen & Launcher',
        'Voice & Chat',
        'Server & Sonstiges'
    )
}
