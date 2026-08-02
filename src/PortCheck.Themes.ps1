<#
================================================================================
 TEE PortChecker - Themes
================================================================================
 Jedes Theme ist ein reiner Satz Farbwerte ("Tokens"). Die Oberfläche
 referenziert diese Werte ausschließlich per DynamicResource, deshalb genügt
 zum Umschalten ein Austausch der Ressourcen - kein Neuaufbau des Fensters,
 kein Neustart.

 EIGENES THEME BAUEN:
   Kopiere einen Block, vergib eine neue Id, ändere die Hex-Werte, fertig.
   Die Testsuite prüft automatisch, dass jedes Theme wirklich ALLE Tokens
   definiert und dass jeder Wert ein gültiger Farbwert ist - vergisst oder
   vertippst du eines, schlägt der Test fehl, statt dass die Oberfläche
   still kaputtgeht.

 Tokens sind Hex-Strings: #RRGGBB oder #AARRGGBB (AA = Deckkraft).

 Lizenz: MIT (siehe LICENSE)
================================================================================
#>

# Alle Tokens, die ein vollständiges Theme definieren muss.
$script:PortCheckThemeTokens = @(
    'WindowBg',      # Fensterhintergrund oben
    'WindowBg2',     # Fensterhintergrund unten (Verlauf)
    'Surface',       # Titelleiste, Seitenleiste, Statusleiste
    'SurfaceAlt',    # abgesetzte Flächen, Tabellenkopf
    'Card',          # Kartenhintergrund
    'CardHover',     # Karte unter dem Mauszeiger
    'Stroke',        # sichtbare Rahmen
    'StrokeSoft',    # dezente Trennlinien
    'Fg',            # Haupttext
    'FgDim',         # Nebentext
    'FgFaint',       # Hinweise, Platzhalter
    'Accent',        # Hauptakzent
    'Accent2',       # zweiter Akzent (Verlaufspartner)
    'AccentFg',      # Text auf Akzentflächen
    'AccentSoft',    # halbtransparenter Akzent für Hover/Auswahl
    'Ok',            # Status offen
    'OkSoft',
    'Bad',           # Status geschlossen / Fehler
    'BadSoft',
    'Warn',          # Status unbekannt / Warnung
    'WarnSoft',
    'Scroll',        # Bildlaufleiste
    'ScrollHover',
    'Gold',          # Gold-Verlauf für den hervorgehobenen Verweis
    'Gold2',
    'GoldFg',        # Text auf Gold
    'CloseHover',    # Schließen-Schaltfläche
    'Shadow'         # Schattenfarbe
)

function Get-PortCheckThemeTokenNames {
    <#
    .SYNOPSIS
        Namen aller Pflicht-Tokens (von der Testsuite benutzt).
    #>
    [CmdletBinding()]
    param()
    return @($script:PortCheckThemeTokens)
}

function Get-PortCheckThemes {
    <#
    .SYNOPSIS
        Alle mitgelieferten Farbwelten in Anzeigereihenfolge.
    .OUTPUTS
        Liste von Objekten mit Id, Name, Tagline, IsDark, Tokens (hashtable)
    #>
    [CmdletBinding()]
    param()

    # Die erste Farbwelt ist zugleich der Notnagel: findet Get-ThemeById eine
    # gespeicherte Id nicht mehr, greift sie auf Themes[0] zurück. Deshalb steht
    # hier die Voreinstellung aus Get-DefaultSettings ganz oben - beides muss
    # zusammenpassen, und ein Test wacht darüber.
    @(
        # ---------------------------------------------------------------------
        [pscustomobject]@{
            Id = 'crimson'; Name = 'Crimson'; Tagline = 'Rot-Orange, aggressiv'; IsDark = $true
            Tokens = @{
                WindowBg   = '#0C0609'; WindowBg2 = '#150A0E'; Surface = '#100709'; SurfaceAlt = '#1B0E13'
                Card       = '#1C0F14'; CardHover = '#26151B'; Stroke  = '#3A1F27'; StrokeSoft = '#2B171E'
                Fg         = '#FAEAEE'; FgDim     = '#C09AA4'; FgFaint = '#8A6670'
                Accent     = '#FF3B5C'; Accent2   = '#FF8A3D'; AccentFg = '#1A0407'; AccentSoft = '#33FF3B5C'
                Ok         = '#42D98A'; OkSoft    = '#2E42D98A'
                Bad        = '#FF3B5C'; BadSoft   = '#2EFF3B5C'
                Warn       = '#FFB020'; WarnSoft  = '#2EFFB020'
                Scroll     = '#4A2530'; ScrollHover = '#663341'
                Gold       = '#FFD770'; Gold2     = '#C98F2B'; GoldFg = '#241800'
                CloseHover = '#E81123'; Shadow    = '#000000'
            }
        }
        # ---------------------------------------------------------------------
        [pscustomobject]@{
            Id = 'midnight'; Name = 'Midnight'; Tagline = 'Cyan auf Tiefschwarz'; IsDark = $true
            Tokens = @{
                WindowBg   = '#070A0F'; WindowBg2 = '#0C1119'; Surface = '#0B1017'; SurfaceAlt = '#111823'
                Card       = '#121A24'; CardHover = '#17212D'; Stroke  = '#22303F'; StrokeSoft = '#1A2530'
                Fg         = '#E9F1FA'; FgDim     = '#93A6BC'; FgFaint = '#5E7288'
                Accent     = '#22D3EE'; Accent2   = '#7C5CFF'; AccentFg = '#04121A'; AccentSoft = '#3322D3EE'
                Ok         = '#3DDC91'; OkSoft    = '#2E3DDC91'
                Bad        = '#FF5470'; BadSoft   = '#2EFF5470'
                Warn       = '#FFB020'; WarnSoft  = '#2EFFB020'
                Scroll     = '#2A3A4C'; ScrollHover = '#3D5065'
                Gold       = '#FFD770'; Gold2     = '#C98F2B'; GoldFg = '#241800'
                CloseHover = '#E81123'; Shadow    = '#000000'
            }
        }
        # ---------------------------------------------------------------------
        [pscustomobject]@{
            Id = 'toxic'; Name = 'Toxic'; Tagline = 'Giftgrün, Terminal-Optik'; IsDark = $true
            Tokens = @{
                WindowBg   = '#050B08'; WindowBg2 = '#08130D'; Surface = '#071009'; SurfaceAlt = '#0C1A12'
                Card       = '#0D1B13'; CardHover = '#12241A'; Stroke  = '#1D3527'; StrokeSoft = '#16291E'
                Fg         = '#E4FBEC'; FgDim     = '#8CB79E'; FgFaint = '#5A8069'
                Accent     = '#3DFF88'; Accent2   = '#00C2A8'; AccentFg = '#02150A'; AccentSoft = '#333DFF88'
                Ok         = '#3DFF88'; OkSoft    = '#2E3DFF88'
                Bad        = '#FF4D5E'; BadSoft   = '#2EFF4D5E'
                Warn       = '#FFD447'; WarnSoft  = '#2EFFD447'
                Scroll     = '#245038'; ScrollHover = '#33704F'
                Gold       = '#FFD770'; Gold2     = '#C98F2B'; GoldFg = '#241800'
                CloseHover = '#E81123'; Shadow    = '#000000'
            }
        }
        # ---------------------------------------------------------------------
        [pscustomobject]@{
            Id = 'ultraviolet'; Name = 'Ultraviolet'; Tagline = 'Violett und Pink'; IsDark = $true
            Tokens = @{
                WindowBg   = '#09070F'; WindowBg2 = '#100B1D'; Surface = '#0C0916'; SurfaceAlt = '#151022'
                Card       = '#161126'; CardHover = '#1E1733'; Stroke  = '#2E2447'; StrokeSoft = '#231B36'
                Fg         = '#EFEAFB'; FgDim     = '#A79BC6'; FgFaint = '#736998'
                Accent     = '#A855F7'; Accent2   = '#EC4899'; AccentFg = '#12061F'; AccentSoft = '#33A855F7'
                Ok         = '#3DDC91'; OkSoft    = '#2E3DDC91'
                Bad        = '#FF5470'; BadSoft   = '#2EFF5470'
                Warn       = '#FFC24B'; WarnSoft  = '#2EFFC24B'
                Scroll     = '#382B55'; ScrollHover = '#4D3B75'
                Gold       = '#FFD770'; Gold2     = '#C98F2B'; GoldFg = '#241800'
                CloseHover = '#E81123'; Shadow    = '#000000'
            }
        }
        # ---------------------------------------------------------------------
        [pscustomobject]@{
            Id = 'amber'; Name = 'Amber'; Tagline = 'Bernstein, warmes Dunkel'; IsDark = $true
            Tokens = @{
                WindowBg   = '#0C0A06'; WindowBg2 = '#14100A'; Surface = '#0F0C07'; SurfaceAlt = '#1A150D'
                Card       = '#1B160E'; CardHover = '#251E14'; Stroke  = '#3A2F1D'; StrokeSoft = '#2B2316'
                Fg         = '#FAF2E4'; FgDim     = '#C0AE8E'; FgFaint = '#8A7B60'
                Accent     = '#FFB020'; Accent2   = '#FF6B35'; AccentFg = '#1A1000'; AccentSoft = '#33FFB020'
                Ok         = '#5FD97A'; OkSoft    = '#2E5FD97A'
                Bad        = '#FF5C5C'; BadSoft   = '#2EFF5C5C'
                Warn       = '#FFD447'; WarnSoft  = '#2EFFD447'
                Scroll     = '#4A3A1E'; ScrollHover = '#66512B'
                Gold       = '#FFD770'; Gold2     = '#C98F2B'; GoldFg = '#241800'
                CloseHover = '#E81123'; Shadow    = '#000000'
            }
        }
        # ---------------------------------------------------------------------
        [pscustomobject]@{
            Id = 'arctic'; Name = 'Arctic'; Tagline = 'Eisblau, ruhig'; IsDark = $true
            Tokens = @{
                WindowBg   = '#070B11'; WindowBg2 = '#0C131C'; Surface = '#0A1018'; SurfaceAlt = '#121B26'
                Card       = '#131C28'; CardHover = '#1A2534'; Stroke  = '#243444'; StrokeSoft = '#1B2836'
                Fg         = '#E8F2FC'; FgDim     = '#93A9C2'; FgFaint = '#61758C'
                Accent     = '#4DA3FF'; Accent2   = '#7CE0FF'; AccentFg = '#03101F'; AccentSoft = '#334DA3FF'
                Ok         = '#4ADE9B'; OkSoft    = '#2E4ADE9B'
                Bad        = '#FF6183'; BadSoft   = '#2EFF6183'
                Warn       = '#FFC24B'; WarnSoft  = '#2EFFC24B'
                Scroll     = '#2B3E52'; ScrollHover = '#3D566F'
                Gold       = '#FFD770'; Gold2     = '#C98F2B'; GoldFg = '#241800'
                CloseHover = '#E81123'; Shadow    = '#000000'
            }
        }
        # ---------------------------------------------------------------------
        [pscustomobject]@{
            Id = 'carbon'; Name = 'Carbon'; Tagline = 'Neutrales Windows-11-Dunkel'; IsDark = $true
            Tokens = @{
                WindowBg   = '#121212'; WindowBg2 = '#181818'; Surface = '#141414'; SurfaceAlt = '#1D1D1D'
                Card       = '#1E1E1E'; CardHover = '#282828'; Stroke  = '#333333'; StrokeSoft = '#262626'
                Fg         = '#F2F2F2'; FgDim     = '#A8A8A8'; FgFaint = '#7A7A7A'
                Accent     = '#4CC2FF'; Accent2   = '#3AA0E0'; AccentFg = '#00131F'; AccentSoft = '#334CC2FF'
                Ok         = '#4CD97C'; OkSoft    = '#2E4CD97C'
                Bad        = '#FF5C5C'; BadSoft   = '#2EFF5C5C'
                Warn       = '#FFC83D'; WarnSoft  = '#2EFFC83D'
                Scroll     = '#3B3B3B'; ScrollHover = '#525252'
                Gold       = '#FFD770'; Gold2     = '#C98F2B'; GoldFg = '#241800'
                CloseHover = '#E81123'; Shadow    = '#000000'
            }
        }
        # ---------------------------------------------------------------------
        [pscustomobject]@{
            Id = 'daylight'; Name = 'Daylight'; Tagline = 'Helles Windows-11-Design'; IsDark = $false
            Tokens = @{
                WindowBg   = '#F5F6F8'; WindowBg2 = '#EDEFF3'; Surface = '#FAFBFC'; SurfaceAlt = '#EEF1F5'
                Card       = '#FFFFFF'; CardHover = '#F4F7FB'; Stroke  = '#D8DEE7'; StrokeSoft = '#E6EAF0'
                Fg         = '#14181F'; FgDim     = '#4C5866'; FgFaint = '#7A8797'
                Accent     = '#0F6CBD'; Accent2   = '#7C5CFF'; AccentFg = '#FFFFFF'; AccentSoft = '#220F6CBD'
                Ok         = '#0E8A4F'; OkSoft    = '#220E8A4F'
                Bad        = '#C42B45'; BadSoft   = '#22C42B45'
                Warn       = '#9A6300'; WarnSoft  = '#229A6300'
                Scroll     = '#C3CBD6'; ScrollHover = '#A5B0BF'
                Gold       = '#E0A62F'; Gold2     = '#A8761D'; GoldFg = '#FFFFFF'
                CloseHover = '#E81123'; Shadow    = '#5A6B80'
            }
        }
    )
}

<#
 ACHTUNG - PowerShell-Falle, die hier mehrfach zuschlägt:

 PowerShell verpackt .NET-Objekte in eine Hülle namens PSObject. Ruft man
 eine .NET-Schnittstelle auf, deren Parameter als "object" deklariert ist -
 und genau das ist der Indexer von ResourceDictionary -, dann wird die HÜLLE
 übergeben, nicht das Objekt darin. WPF sieht dann keinen Brush, sondern
 etwas Unbekanntes, und wirft beim nächsten Neuzeichnen:

     "#FF0B1017" ist kein gültiger Wert für die Eigenschaft "Background".

 Verwirrend daran: liest man den Wert danach wieder aus, meldet GetType()
 brav "SolidColorBrush" - weil PowerShell beim Lesen automatisch auspackt.
 Der Fehler ist also nur von außen sichtbar.

 Gegenmittel: an jeder Übergabestelle einen ausdrücklichen Cast auf den
 Zieltyp setzen. Das zwingt PowerShell, das nackte Objekt herauszugeben.
 Deshalb steht unten überall [System.Windows.Media.Brush] bzw.
 [System.Windows.Media.Color] davor - das ist kein überflüssiger Zierrat.
#>

function ConvertTo-PortCheckBrush {
    <#
    .SYNOPSIS
        Wandelt einen Hex-Farbwert in einen eingefrorenen SolidColorBrush.
    .DESCRIPTION
        Eingefroren (Freeze) bedeutet: unveränderlich, dadurch threadsicher
        und schneller im Rendering.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Hex)

    $color = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $brush = New-Object System.Windows.Media.SolidColorBrush($color)
    $brush.Freeze()
    return ([System.Windows.Media.Brush]$brush)
}

function Set-PortCheckTheme {
    <#
    .SYNOPSIS
        Trägt ein Theme in die Ressourcen eines Fensters ein.
    .DESCRIPTION
        Setzt pro Token zwei Ressourcen:
          <Name>Color  -> Color  (für Verläufe und Schatten)
          <Name>Brush  -> Brush  (für Flächen, Text, Rahmen)
        Zusätzlich einen fertigen Akzent-Verlauf "AccentGradientBrush".

        Weil die Oberfläche überall DynamicResource benutzt, aktualisiert
        sich das Fenster sofort.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Window]$Window,
        [Parameter(Mandatory = $true)]$Theme
    )

    foreach ($token in $script:PortCheckThemeTokens) {
        $hex = $Theme.Tokens[$token]
        if (-not $hex) { throw "Theme '$($Theme.Id)': Token '$token' fehlt." }

        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $brush = New-Object System.Windows.Media.SolidColorBrush($color)
        $brush.Freeze()

        # Casts sind Pflicht - siehe Hinweis zur PSObject-Hülle weiter oben.
        $Window.Resources[($token + 'Color')] = [System.Windows.Media.Color]$color
        $Window.Resources[($token + 'Brush')] = [System.Windows.Media.Brush]$brush
    }

    # Akzent-Verlauf für Schaltflächen und Hervorhebungen
    $gradient = New-Object System.Windows.Media.LinearGradientBrush
    $gradient.StartPoint = New-Object System.Windows.Point(0, 0)
    $gradient.EndPoint   = New-Object System.Windows.Point(1, 1)
    $gradient.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Theme.Tokens['Accent']), 0)))
    $gradient.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Theme.Tokens['Accent2']), 1)))
    $gradient.Freeze()
    $Window.Resources['AccentGradientBrush'] = [System.Windows.Media.Brush]$gradient

    # Gold-Verlauf für den hervorgehobenen Verweis in der Seitenleiste.
    # Drei Stufen (dunkel - hell - dunkel), damit die Fläche gewölbt wirkt und
    # der darüberlaufende Glanz etwas hat, worauf er aufsetzen kann.
    $gold = New-Object System.Windows.Media.LinearGradientBrush
    $gold.StartPoint = New-Object System.Windows.Point(0, 0)
    $gold.EndPoint   = New-Object System.Windows.Point(1, 1)
    $gold.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Theme.Tokens['Gold2']), 0)))
    $gold.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Theme.Tokens['Gold']), 0.5)))
    $gold.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Theme.Tokens['Gold2']), 1)))
    $gold.Freeze()
    $Window.Resources['GoldGradientBrush'] = [System.Windows.Media.Brush]$gold

    # Sehr dezenter Verlauf für den Fensterhintergrund
    $bg = New-Object System.Windows.Media.LinearGradientBrush
    $bg.StartPoint = New-Object System.Windows.Point(0, 0)
    $bg.EndPoint   = New-Object System.Windows.Point(0.4, 1)
    $bg.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Theme.Tokens['WindowBg']), 0)))
    $bg.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($Theme.Tokens['WindowBg2']), 1)))
    $bg.Freeze()
    $Window.Resources['WindowBackgroundBrush'] = [System.Windows.Media.Brush]$bg

    $Window.Resources['CurrentThemeIsDark'] = [bool]$Theme.IsDark
}

function Get-StatusBrushSet {
    <#
    .SYNOPSIS
        Liefert die Statusfarben des Themes als fertige Pinsel.
    .DESCRIPTION
        Ergebniszeilen bekommen ihre Farbe als echtes Brush-Objekt direkt am
        Datensatz. Das ist deutlich robuster als Bindungen mit Konvertern und
        funktioniert zuverlässig mit PowerShell-Objekten.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Theme)

    @{
        Open    = @{ Fg = (ConvertTo-PortCheckBrush $Theme.Tokens['Ok']);      Bg = (ConvertTo-PortCheckBrush $Theme.Tokens['OkSoft']) }
        Closed  = @{ Fg = (ConvertTo-PortCheckBrush $Theme.Tokens['Bad']);     Bg = (ConvertTo-PortCheckBrush $Theme.Tokens['BadSoft']) }
        Unknown = @{ Fg = (ConvertTo-PortCheckBrush $Theme.Tokens['Warn']);    Bg = (ConvertTo-PortCheckBrush $Theme.Tokens['WarnSoft']) }
        Error   = @{ Fg = (ConvertTo-PortCheckBrush $Theme.Tokens['FgDim']);   Bg = (ConvertTo-PortCheckBrush $Theme.Tokens['StrokeSoft']) }
    }
}
