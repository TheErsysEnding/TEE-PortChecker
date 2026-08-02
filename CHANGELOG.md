# Änderungen

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
Versionierung nach [SemVer](https://semver.org/lang/de/).

## [2.0.0] — 2026-08-02

Vollständiger Neuaufbau. Aus einem einzelnen Konsolenskript wurde ein Werkzeug
mit grafischer Oberfläche, getrennter Messlogik und Testsuite.

### Neu

- **Grafische Oberfläche** im Windows-11-Stil mit eigener Titelleiste,
  Seitenleiste und Kartenlayout (WPF, zur Laufzeit aus `Gui.xaml` geladen)
- **Acht Farbwelten** — Midnight, Toxic, Crimson, Ultraviolet, Amber, Arctic,
  Carbon, Daylight — im Betrieb umschaltbar, Auswahl wird gemerkt
- **83 Spiele-Presets** statt bisher 10, mit Kategorien, Plattform-Varianten und
  Quellenangabe je Eintrag. Konsolen-Fassungen erben die Basisports ihrer
  Plattform über `BaseId`, statt sie zu wiederholen
- **Messung im Hintergrund-Runspace** — die Oberfläche friert nicht mehr ein, der
  Abbrechen-Knopf reagiert sofort
- **Export** als CSV, JSON oder Textbericht
- **Filter und Suche** über Ergebnisse und Presets
- **Netzwerkübersicht** mit Adaptern, Gateway, DNS und UPnP-Geräteliste
- **Einstellungen** für Pausenlänge, Zeitlimit und Listener-Verhalten,
  gespeichert in `%APPDATA%\PortCheck\settings.json`
- **Testsuite** mit 87 Tests ohne Fremdmodule, komplett offline lauffähig
- **Konsolenfassung** mit Schaltern für Automatisierung (`-Ports`, `-Preset`,
  `-Csv`, `-NatOnly`, `-NonInteractive`)

### Geändert

- Messlogik vollständig von der Anzeige getrennt (`PortCheck.Core.ps1` enthält
  kein `Write-Host` und kein Fenster mehr). Oberfläche, Konsolenfassung und
  Hintergrund-Runspaces benutzen jetzt denselben Code
- NAT-Bewertung benennt das gemessene Verhalten nach RFC 5780 und sagt
  ausdrücklich, dass das Filter-Verhalten nicht messbar ist
- STUN-Abfrage nutzt fünf statt vier Server
- Ungültige Eingaben werden nicht mehr stillschweigend verworfen, sondern
  zurückgemeldet
- Quelldateien liegen als UTF-8 mit BOM vor, damit Umlaute unter Windows
  PowerShell 5.1 korrekt dargestellt werden

### Behoben

- **CGNAT wurde nicht erkannt.** Eine von außen gesehene Adresse aus
  `100.64.0.0/10` wird jetzt als solche gemeldet — dort ist Portweiterleitung
  technisch unmöglich, egal was im Router steht
- **Der Start-Vorgang wurde nie abgeschlossen.** Dadurch galt die Anwendung
  weiter als beschäftigt und lehnte die erste Messung mit „Es läuft bereits eine
  Messung" ab
- STUN-Antworten werden gegen Länge und Attributgrenzen geprüft, statt bei einem
  abgeschnittenen Paket über das Pufferende hinauszulesen
- Bereichsangaben oberhalb von 65535 werden abgewiesen statt zurechtgebogen
- Ausgehende Anfragen tragen einen eigenen User-Agent; manche Dienste blockten
  den PowerShell-Standardwert

## [1.0.0]

- Konsolenskript mit Menü, Gaming-Presets, NAT-Typ-Test über STUN, UPnP-Erkennung
  und CSV-Export
