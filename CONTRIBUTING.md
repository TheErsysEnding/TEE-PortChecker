# Mitmachen

Danke, dass du dir das Projekt anschaust. Es gibt keine Formalitäten — ein Issue
oder ein Pull Request genügt.

## Am hilfreichsten: Portlisten korrigieren

Hersteller ändern Ports ohne Ankündigung, und niemand kann alle Spiele im Blick
behalten. **Wenn dir eine falsche oder fehlende Portliste auffällt, ist das die
wertvollste Meldung überhaupt.**

Alle Portdaten stehen in genau einer Datei: [`src/PortCheck.Presets.ps1`](src/PortCheck.Presets.ps1).

Ein Eintrag sieht so aus:

```powershell
New-PortCheckPreset -Id 'bo2-ps3' -Name 'Black Ops II (PS3)' -Category 'Call of Duty' `
    -Platform 'PS3' -Vendor 'Treyarch' -Year 2012 `
    -BaseId 'ps3' -TCP @(3074) -UDP @(3074, 3075) `
    -Note 'PSN-Basisports plus CoD-Spielport.' -Source $codSrc
```

Wichtig dabei:

- **`-BaseId` benutzen, wenn es eine Konsolenfassung ist.** Dann erbt der Eintrag
  automatisch die Basisports der Plattform (`ps3`, `ps4`, `xbox360` …) und du
  trägst nur die titelspezifischen Ports ein. Nicht die Plattform-Ports abtippen —
  sonst driften die Listen mit der Zeit auseinander.
- **`-Source` mit der Hersteller-Seite füllen.** Ohne nachprüfbare Quelle ist eine
  Portliste nur ein Gerücht.
- **UDP mit eintragen**, auch wenn es nicht von außen prüfbar ist. Die Ports müssen
  trotzdem im Router freigegeben werden, und die Oberfläche zeigt sie als Hinweis.

Danach die Tests laufen lassen — sie prüfen automatisch auf doppelte Ids,
ungültige Portnummern, ins Leere zeigende `BaseId`-Verweise und unbekannte
Kategorien.

## Eigene Farbwelt beisteuern

In [`src/PortCheck.Themes.ps1`](src/PortCheck.Themes.ps1) einen Block kopieren,
neue `Id` vergeben, Hex-Werte ändern. Die Testsuite prüft, dass **jedes** Token
vorhanden und jeder Farbwert gültig ist — vergisst du eines, wird der Test rot,
statt dass die Oberfläche still kaputtgeht.

Bitte auf Lesbarkeit achten: Text auf Hintergrund sollte auch bei schlechtem
Monitor noch gut zu lesen sein.

## Vor dem Pull Request

```powershell
.\tests\Run-Tests.ps1        # muss grün sein
.\src\PortCheck.Gui.ps1 -SelfTest
```

## Regeln für den Quelltext

Ein paar Dinge, die uns beim Bauen schon auf die Füße gefallen sind und die
deshalb festgehalten sind:

1. **Dateien als UTF-8 MIT BOM speichern.** Ohne BOM liest Windows PowerShell 5.1
   die Datei als ANSI und macht aus jedem Umlaut Datenmüll. Ein Test prüft das ab.

2. **Kein `@()` um eine `List[object]`.** Auf manchen PowerShell-5.1-Builds wirft
   das eine `ArgumentException`. `.ToArray()` benutzen. Auch das prüft ein Test.

3. **Bei `.NET`-Aufrufen mit `object`-Parametern ausdrücklich casten.**
   PowerShell reicht sonst die `PSObject`-Hülle durch statt des Objekts selbst.
   Betrifft vor allem `$Window.Resources[...] = [System.Windows.Media.Brush]$brush`.
   Der Fehler zeigt sich erst zur Laufzeit und liest sich völlig irreführend.

4. **`.GetNewClosure()` nur mit gutem Grund.** Eine so erzeugte Closure bekommt
   ein eigenes Modul, und darin zeigt `$script:` auf dessen eigene Ebene — nicht
   mehr auf das Skript. Handler greifen dann ins Leere.

5. **Keine Farbe fest ins XAML schreiben.** Alle Farben kommen per
   `DynamicResource` aus der Theme-Datei, sonst lässt sich das Element nicht
   umfärben. Ein Test prüft auch das.

6. **`PortCheck.Core.ps1` bleibt frei von Oberfläche.** Kein `Write-Host`, kein
   Fenster, keine Rückfragen — nur Objekte zurückgeben. Nur so können Oberfläche,
   Konsolenfassung und Hintergrund-Runspaces denselben Code benutzen.

7. **Genehmigte PowerShell-Verben benutzen** (`Get-`, `Set-`, `Test-`, `Show-`,
   `Start-` …). `Build-` oder `Use-` sind es nicht.

## Umgangston

Kritik am Code ist willkommen und erwünscht. Kritik an Personen nicht.
