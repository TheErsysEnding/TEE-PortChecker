#Requires -Version 5.1
<#
================================================================================
 TEE PortChecker - Programmsymbol erzeugen
================================================================================
 Erzeugt docs/TEE-PortChecker.ico aus reiner Geometrie.

 WARUM SELBST GEZEICHNET:
   Ein Emoji wäre naheliegend, ist aber lizenzrechtlich heikel. Emoji-Schriften
   gehören jemandem: "Segoe UI Emoji" ist Microsofts Eigentum und darf nicht
   einfach in ein fremdes Programm übernommen werden, Twemoji verlangt eine
   Namensnennung, OpenMoji zusätzlich die Weitergabe unter gleichen Bedingungen.
   Für ein Symbol, das in jedem Explorer-Fenster und in der Taskleiste steht,
   ist das unnötiger Ärger.

   Deshalb besteht der Globus hier aus Kreisen und Linien, die dieses Skript
   selbst zeichnet. Kein fremdes Material, keine Namensnennung, keine
   Einschränkung - und die Farben passen zur Anwendung.

 ZWEI FASSUNGEN:
   Bis 32 Bildpunkte nur der Globus, darüber Globus plus Schriftzug. Bei
   16 Bildpunkten wäre "TEE" vier Punkte hoch und damit unlesbarer Matsch -
   ein Symbol, das man nicht erkennt, ist wertlos.

 Aufruf:  .\tools\New-AppIcon.ps1
================================================================================
#>

param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'docs\TEE-PortChecker.ico')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Farben der Standard-Farbwelt "Crimson"
$FarbeA  = '#FF3B5C'   # Akzent
$FarbeB  = '#FF8A3D'   # Verlaufspartner
$FarbeFg = '#FFF3F5'   # Globus und Schrift

function New-IconVisual {
    <#
    .SYNOPSIS
        Baut das Symbol als Elementbaum in der gewünschten Kantenlänge.
    #>
    param(
        [Parameter(Mandatory = $true)][int]$Size,
        [switch]$WithText
    )

    $wurzel = New-Object System.Windows.Controls.Grid
    $wurzel.Width  = $Size
    $wurzel.Height = $Size

    # Hintergrund: abgerundetes Quadrat mit Verlauf
    $flaeche = New-Object System.Windows.Controls.Border
    $flaeche.CornerRadius = New-Object System.Windows.CornerRadius($Size * 0.22)
    $verlauf = New-Object System.Windows.Media.LinearGradientBrush
    $verlauf.StartPoint = New-Object System.Windows.Point(0, 0)
    $verlauf.EndPoint   = New-Object System.Windows.Point(1, 1)
    $verlauf.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($FarbeA), 0)))
    $verlauf.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [System.Windows.Media.ColorConverter]::ConvertFromString($FarbeB), 1)))
    $flaeche.Background = $verlauf
    [void]$wurzel.Children.Add($flaeche)

    $vordergrund = New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.ColorConverter]::ConvertFromString($FarbeFg))

    # Maße je nach Fassung
    if ($WithText) {
        $mitteX  = $Size * 0.5
        $mitteY  = $Size * 0.395
        $radius  = $Size * 0.215
        $strich  = [Math]::Max(1.0, $Size * 0.030)
    } else {
        $mitteX  = $Size * 0.5
        $mitteY  = $Size * 0.5
        $radius  = $Size * 0.30
        $strich  = [Math]::Max(1.2, $Size * 0.055)
    }

    $leinwand = New-Object System.Windows.Controls.Canvas
    [void]$wurzel.Children.Add($leinwand)

    function Add-Ellipse {
        param($Canvas, [double]$CX, [double]$CY, [double]$RX, [double]$RY, [double]$Thickness, $Brush)
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width  = $RX * 2
        $e.Height = $RY * 2
        $e.Stroke = $Brush
        $e.StrokeThickness = $Thickness
        [System.Windows.Controls.Canvas]::SetLeft($e, $CX - $RX)
        [System.Windows.Controls.Canvas]::SetTop($e, $CY - $RY)
        [void]$Canvas.Children.Add($e)
    }
    function Add-Line {
        param($Canvas, [double]$X1, [double]$Y1, [double]$X2, [double]$Y2, [double]$Thickness, $Brush)
        $l = New-Object System.Windows.Shapes.Line
        $l.X1 = $X1; $l.Y1 = $Y1; $l.X2 = $X2; $l.Y2 = $Y2
        $l.Stroke = $Brush
        $l.StrokeThickness = $Thickness
        $l.StrokeStartLineCap = 'Round'
        $l.StrokeEndLineCap   = 'Round'
        [void]$Canvas.Children.Add($l)
    }

    # Globus: Umriss, ein Längenkreis, drei Breitenkreise.
    #
    # Die Breitenkreise werden um die halbe Strichstärke gekürzt. Ohne das
    # ragen die runden Linienenden über den Umriss hinaus und der Globus
    # bekommt kleine Nasen an den Seiten.
    $kuerzung = $strich * 0.5

    Add-Ellipse $leinwand $mitteX $mitteY $radius $radius $strich $vordergrund
    Add-Ellipse $leinwand $mitteX $mitteY ($radius * 0.42) $radius $strich $vordergrund

    $mittelHalb = $radius - $kuerzung
    Add-Line $leinwand ($mitteX - $mittelHalb) $mitteY ($mitteX + $mittelHalb) $mitteY $strich $vordergrund

    # Die beiden äusseren Breitenkreise nur, wenn genug Platz ist - sonst
    # verschmieren sie den Globus zu einem Klecks.
    if ($radius -ge 14) {
        $abstand = $radius * 0.52
        $halb    = [Math]::Sqrt([Math]::Max(0.0, ($radius * $radius) - ($abstand * $abstand))) - $kuerzung
        if ($halb -gt 0) {
            Add-Line $leinwand ($mitteX - $halb) ($mitteY - $abstand) ($mitteX + $halb) ($mitteY - $abstand) ($strich * 0.85) $vordergrund
            Add-Line $leinwand ($mitteX - $halb) ($mitteY + $abstand) ($mitteX + $halb) ($mitteY + $abstand) ($strich * 0.85) $vordergrund
        }
    }

    if ($WithText) {
        $schrift = New-Object System.Windows.Controls.TextBlock
        $schrift.Text       = 'TEE'
        $schrift.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Variable Display, Segoe UI, Arial')
        $schrift.FontWeight = [System.Windows.FontWeights]::Bold
        $schrift.FontSize   = $Size * 0.235
        $schrift.Foreground = $vordergrund
        $schrift.HorizontalAlignment = 'Center'
        $schrift.VerticalAlignment   = 'Bottom'
        $schrift.Margin = New-Object System.Windows.Thickness(0, 0, 0, $Size * 0.10)
        # Etwas Sperrung, damit die drei Buchstaben nicht zusammenkleben
        $schrift.SetValue([System.Windows.Controls.TextBlock]::TextAlignmentProperty,
                          [System.Windows.TextAlignment]::Center)
        [void]$wurzel.Children.Add($schrift)
    }

    $wurzel.Measure((New-Object System.Windows.Size($Size, $Size)))
    $wurzel.Arrange((New-Object System.Windows.Rect(0, 0, $Size, $Size)))
    $wurzel.UpdateLayout()
    return $wurzel
}

function Get-PngBytes {
    <#
    .SYNOPSIS
        Zeichnet das Symbol und gibt die PNG-Daten zurück.
    #>
    param([Parameter(Mandatory = $true)][int]$Size)

    $mitText = ($Size -ge 48)
    $visual  = if ($mitText) { New-IconVisual -Size $Size -WithText } else { New-IconVisual -Size $Size }

    # Werte vorher berechnen: schreibt man Ausdrücke direkt in die Klammer
    # hinter New-Object, fasst PowerShell sie zu einem Array zusammen.
    $kante = [int]$Size
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap -ArgumentList @(
        $kante, $kante, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)

    $kodierer = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $kodierer.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $strom = New-Object System.IO.MemoryStream
    try {
        $kodierer.Save($strom)
        # Das Komma ist Pflicht: ohne es entrollt PowerShell das Byte-Array
        # beim Zurückgeben in einzelne Werte, und der Aufrufer bekommt ein
        # object[] statt byte[]. BinaryWriter waehlt dann die Ueberladung fuer
        # ein EINZELNES Byte - die ICO-Datei bestuende danach nur noch aus
        # Kopf, Verzeichnis und acht einzelnen Bytes.
        return ,$strom.ToArray()
    } finally { $strom.Dispose() }
}

function Write-IcoFile {
    <#
    .SYNOPSIS
        Packt mehrere PNG-Bilder in eine ICO-Datei.
    .DESCRIPTION
        Der Aufbau einer ICO-Datei ist überschaubar:
          6 Byte Kopf, dann je 16 Byte Verzeichniseintrag, dann die Bilddaten.
        Windows versteht seit Vista PNG-Daten direkt in der ICO - damit
        entfällt der umständliche Weg über Bitmaps mit Maske.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Images   # Größe -> Byte[]
    )

    $groessen = @($Images.Keys | Sort-Object)
    $verzeichnis = New-Object System.IO.MemoryStream
    $schreiber   = New-Object System.IO.BinaryWriter($verzeichnis)

    $schreiber.Write([UInt16]0)                    # reserviert
    $schreiber.Write([UInt16]1)                    # Typ 1 = Symbol
    $schreiber.Write([UInt16]$groessen.Count)

    # Die Bilddaten beginnen hinter Kopf und Verzeichnis.
    $versatz = 6 + (16 * $groessen.Count)
    foreach ($g in $groessen) {
        $daten = $Images[$g]
        # 256 wird als 0 geschrieben - ein Byte kann 256 nicht darstellen.
        $kante = if ($g -ge 256) { 0 } else { $g }
        $schreiber.Write([Byte]$kante)             # Breite
        $schreiber.Write([Byte]$kante)             # Höhe
        $schreiber.Write([Byte]0)                  # Farbanzahl (0 = mehr als 256)
        $schreiber.Write([Byte]0)                  # reserviert
        $schreiber.Write([UInt16]1)                # Ebenen
        $schreiber.Write([UInt16]32)               # Bit je Bildpunkt
        $schreiber.Write([UInt32]$daten.Length)
        $schreiber.Write([UInt32]$versatz)
        $versatz += $daten.Length
    }
    # Cast auf byte[] als zweite Absicherung - siehe Hinweis in Get-PngBytes.
    foreach ($g in $groessen) { $schreiber.Write([byte[]]$Images[$g]) }

    $schreiber.Flush()
    $ordner = Split-Path -Parent $Path
    if ($ordner -and -not (Test-Path $ordner)) { New-Item -ItemType Directory -Path $ordner -Force | Out-Null }
    [System.IO.File]::WriteAllBytes($Path, $verzeichnis.ToArray())
    $schreiber.Dispose()
}

# ------------------------------------------------------------------------------

$groessen = @(16, 20, 24, 32, 48, 64, 128, 256)
$bilder = @{}
foreach ($g in $groessen) {
    $bilder[$g] = Get-PngBytes -Size $g
    "  {0,3} x {1,-3}  {2,6} Byte  {3}" -f $g, $g, $bilder[$g].Length, $(if ($g -ge 48) { 'mit Schriftzug' } else { 'nur Globus' })
}

Write-IcoFile -Path $OutputPath -Images $bilder
""
"Symbol geschrieben: $OutputPath  ($([int]((Get-Item $OutputPath).Length / 1KB)) KB, $($groessen.Count) Größen)"
