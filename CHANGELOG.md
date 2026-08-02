# Änderungen

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
Versionierung nach [SemVer](https://semver.org/lang/de/).

## [1.0.0] — 2026-08-02

Erste Veröffentlichung von **TEE PortChecker**.

Entstanden aus einem privaten Konsolenskript, das nur ein Menü und zehn
Portlisten hatte. Daraus wurde ein Werkzeug mit grafischer Oberfläche,
sauber getrennter Messlogik und einer Testsuite.

### Enthalten

- **Grafische Oberfläche** im Windows-11-Stil mit eigener Titelleiste,
  Seitenleiste und Kartenlayout (WPF, zur Laufzeit aus `Gui.xaml` geladen)
- **Willkommensfenster** beim ersten Start, jederzeit wieder aufrufbar unter
  „Über & Hilfe"
- **Acht Farbwelten** — Midnight, Toxic, Crimson, Ultraviolet, Amber, Arctic,
  Carbon, Daylight — im laufenden Betrieb umschaltbar, Auswahl wird gemerkt
- **83 Spiele-Presets** mit Kategorien, Plattform-Varianten und Quellenangabe je
  Eintrag. Konsolen-Fassungen erben die Basisports ihrer Plattform über `BaseId`,
  statt sie zu wiederholen — dadurch stehen Portdaten nur an einer Stelle
- **Port-Test** für einzelne Ports, Bereiche und Mischungen, mit Live-Ergebnissen,
  Filter und Abbruch jederzeit
- **NAT-Typ-Messung** per STUN über fünf Server und einen gemeinsamen Socket,
  inklusive CGNAT-Erkennung
- **Netzwerkübersicht** mit Adaptern, Gateway, DNS und UPnP-Geräteliste
- **Export** als CSV, JSON oder Textbericht
- **Konsolenfassung** mit Schaltern für Automatisierung (`-Ports`, `-Preset`,
  `-Csv`, `-NatOnly`, `-ListPresets`, `-NonInteractive`)
- **Einstellungen** für Pausenlänge, Zeitlimit und Listener-Verhalten,
  gespeichert in `%APPDATA%\TEE-PortChecker\settings.json`
- **Testsuite** mit 100 Tests ohne Fremdmodule, komplett offline lauffähig

### Gegenüber dem privaten Vorläufer behoben

- **CGNAT wurde nicht erkannt.** Eine von außen gesehene Adresse aus
  `100.64.0.0/10` wird jetzt als solche gemeldet — dort ist Portweiterleitung
  technisch unmöglich, egal was im Router steht
- **Der Start-Vorgang wurde nie abgeschlossen.** Dadurch galt die Anwendung
  weiter als beschäftigt und lehnte die erste Messung mit „Es läuft bereits eine
  Messung" ab
- STUN-Antworten werden gegen Länge und Attributgrenzen geprüft, statt bei einem
  abgeschnittenen Paket über das Pufferende hinauszulesen
- Bereichsangaben oberhalb von 65535 werden abgewiesen statt zurechtgebogen
- Ungültige Eingaben werden zurückgemeldet statt stillschweigend verworfen
- Ausgehende Anfragen tragen einen eigenen User-Agent; manche Dienste blockten
  den PowerShell-Standardwert
- Messung läuft im Hintergrund-Runspace: die Oberfläche friert nicht mehr ein und
  der Abbrechen-Knopf reagiert sofort

### Bekannte Grenzen

Kein Fehler, sondern Physik — steht deshalb auch in der Anwendung selbst:

- UDP-Ports lassen sich von außen nicht zuverlässig prüfen
- Beim NAT-Typ ist nur das Mapping-Verhalten messbar (RFC 5780), nicht das
  Filter-Verhalten
- Der Port-Test braucht zwingend einen Dienst außerhalb des eigenen Netzes
