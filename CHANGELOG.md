# Änderungen

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
Versionierung nach [SemVer](https://semver.org/lang/de/).

## [1.1.0] — 2026-08-02

### Neu

- **Portfreigaben im Router verwalten.** Bisher wurde UPnP nur erkannt — jetzt
  lassen sich vorhandene Freigaben ansehen, neue anlegen und alte entfernen,
  ohne das Router-Menü zu suchen. Freigaben auf bekannten Risiko-Ports werden
  farblich hervorgehoben; vor dem Öffnen eines Wegs aus dem Internet wird
  ausdrücklich nachgefragt.
- **Sicherheits-Check** über 20 Ports, die aus dem Internet erreichbar ein
  echtes Risiko wären. Zu jedem Fund steht, was ein Angreifer damit anfangen
  könnte — eine Warnung ohne Begründung nimmt niemand ernst.
- **IPv6-Prüfung** auf der NAT-Seite. Für alle, die bei IPv4 an CGNAT hängen,
  ist das die eigentlich wichtige Frage: über IPv6 braucht es gar keine
  Portweiterleitung.
- **Verbindungsqualität**: Antwortzeit, Schwankung und Paketverlust entlang der
  Kette PC → Router → Anbieter → Internet. Wo die Werte zum ersten Mal schlecht
  werden, dort sitzt das Problem.
- **Ergebnis teilen**: eine Karte fürs Weitergeben, die beim Öffnen direkt in
  der Zwischenablage landet. Die öffentliche IP wird dabei gekürzt — die Karte
  ist zum Teilen gedacht.
- Seite **„Ports öffnen"** mit Router-Anleitung, Menüpfaden der verbreitetsten
  Hersteller und einer ehrlichen Einordnung, wann es nicht am Router liegt.

### Behoben

- **Die Anwendung war nach einem Klick im Willkommensfenster unerreichbar.** Der
  modale Dialog ging auf, bevor das Hauptfenster gezeichnet war; das
  Hauptfenster blieb dadurch unsichtbar, hatte aber den Taskleisten-Eintrag,
  während das sichtbare Fenster keinen hatte. Nahm ein anderes Programm den
  Fokus, war nur noch Alt+Tab übrig.
- **Die UPnP-Suche gab dem Router die Schuld, wenn Windows schuld war.** Stuft
  Windows das Netzwerk als „öffentlich" ein, blockiert die Firewall die
  Antworten des Routers — die Suche kann dann gar nichts finden. Dieser Fall
  wird jetzt erkannt und erklärt.
- **SSDP-Suche verlor Pakete** und nutzte auf Rechnern mit mehreren Adaptern
  womöglich den falschen. Die Anfrage geht jetzt gebunden an die richtige
  Adresse hinaus, mehrfach und mit mehreren Suchbegriffen.
- **Fehlernummern des Routers gingen verloren.** Bei einer Ablehnung stand
  überall nur „Fehler 0" statt „Port bereits vergeben" — der Antwortkörper war
  zu diesem Zeitpunkt bereits verbraucht. Die SOAP-Aufrufe laufen deshalb jetzt
  über `HttpWebRequest`.
- Eine unlesbare Antwort des Routers wurde als Ablehnung ausgegeben. Beides ist
  jetzt unterscheidbar.
- **Adaptergeschwindigkeit wurde binär statt dezimal umgerechnet.** Aus echten
  576 Mbit/s wurden angezeigte 549 — rund 5 % zu wenig, bei jedem Adapter.
- **Virtuelle Adapter zeigten eine Fantasiezahl als Geschwindigkeit.** Ein
  WireGuard-Tunnel meldet stur 100 Gbit/s, weil es keine physische Leitung gibt,
  deren Tempo man ablesen könnte. Statt der Zahl steht dort jetzt „Tunnel — keine
  echte Leitung".
- **Ein aktives VPN blieb unerwähnt.** Läuft der Verkehr durch einen Tunnel,
  messen Port-Test und NAT-Typ den Ausgang des VPN-Anbieters und nicht den
  eigenen Anschluss — die Ergebnisse bedeuten dann etwas völlig anderes. Das
  Werkzeug erkennt das jetzt und sagt es deutlich.

### Sonstiges

- **Crimson ist die neue Voreinstellung** und steht an erster Stelle der
  Farbwelten, damit sie auch der Rückfallwert ist.
- Testsuite von 100 auf 144 Tests. Neu darunter ein **nachgebauter
  UPnP-Router**, gegen den der komplette Weg geprüft wird: Beschreibung lesen,
  Steuer-Adresse finden, auflisten, anlegen, löschen — samt der Fehlernummern,
  die echte Geräte zurückgeben. So ist die Funktion abgesichert, ohne bei jedem
  Testlauf Ports in fremden Netzen zu öffnen.

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
- **Seite „Ports öffnen"** mit Schritt-für-Schritt-Anleitung zur
  Portweiterleitung, Menüpfaden der verbreitetsten Router und einer ehrlichen
  Einordnung, wann es nicht am Router liegt (CGNAT, doppeltes NAT, Mobilfunk)
- **Testsuite** mit 102 Tests ohne Fremdmodule, komplett offline lauffähig

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
