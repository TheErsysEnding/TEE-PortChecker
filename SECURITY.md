# Sicherheit und Datenschutz

## Was TEE PortChecker tut — und was nicht

TEE PortChecker öffnet Netzwerkverbindungen. Deshalb steht hier vollständig, was dabei
passiert. Nachprüfen lässt sich alles im Quelltext; es gibt keine kompilierte
Datei, der du vertrauen musst.

### Ausgehende Verbindungen

| Funktion | Ziel | Was übertragen wird |
|---|---|---|
| Port-Test | `ports.yougetsignal.com`, ersatzweise `canyouseeme.org` | deine öffentliche IP-Adresse und die Portnummer |
| IP ermitteln | `api.ipify.org`, `ifconfig.me`, `checkip.amazonaws.com`, `icanhazip.com` | nur die Anfrage selbst |
| NAT-Typ | `stun.l.google.com`, `stun1.l.google.com`, `stun.cloudflare.com`, `stun.nextcloud.com`, `stun.sipgate.net` | leere STUN-Binding-Anfragen, keine Inhalte |
| UPnP-Suche | SSDP-Multicast `239.255.255.250:1900` | verlässt das lokale Netz nicht |

Der Port-Test **braucht** einen Rechner außerhalb deines Netzes — anders lässt
sich Erreichbarkeit von außen nicht feststellen. Wer das nicht möchte, kann diese
Funktion einfach nicht benutzen; NAT-Test und Netzwerkübersicht funktionieren
unabhängig davon.

### Was lokal gespeichert wird

Ausschließlich `%APPDATA%\TEE-PortChecker\settings.json` mit Farbwelt, Pausenlänge,
Zeitlimit und der zuletzt eingegebenen Portliste.

**Nicht gespeichert werden:** Messergebnisse, IP-Adressen, Verlauf, Kennungen
jeder Art. Exportdateien entstehen nur, wenn du sie ausdrücklich anlegst.

Es gibt keine Telemetrie, keine Absturzberichte, keine Konten, keine Werbung und
keine Auto-Updates.

### Lokale Listener

Beim Prüfen öffnet TEE PortChecker kurzzeitig einen TCP-Listener auf dem jeweiligen
Port und schließt ihn sofort wieder. Der Listener nimmt Verbindungen an, aber
liest oder sendet **keine Daten**. Ohne ihn würde selbst eine korrekt
eingerichtete Portweiterleitung „geschlossen" melden.

Das löst beim ersten Start eine Windows-Firewall-Abfrage aus. Diese Freigabe ist
für die Messung erforderlich. Wer sie nicht erteilen möchte, kann in den
Einstellungen „lokalen Listener öffnen" abschalten — dann ist das Ergebnis aber
weniger aussagekräftig.

### Rechte

TEE PortChecker läuft ohne Adminrechte, ändert keine Systemeinstellungen, schreibt
nichts in die Registry und installiert nichts.

## Lücke melden

Wenn du ein Sicherheitsproblem findest, melde es bitte über eine
[GitHub Security Advisory](https://github.com/TheErsysEnding/TEE-PortChecker/security/advisories/new)
oder als privates Issue — nicht als öffentlichen Bugreport, solange es
ungepatcht ist.

Bitte mit dabei: was passiert, wie man es nachstellt, und welche Windows- und
PowerShell-Version du benutzt (`$PSVersionTable`).

## Was hier ausdrücklich kein Sicherheitsproblem ist

- **„Alle meine Ports sind zu."** Das ist meistens die richtige Antwort. Offene
  Ports ins Internet sind die Ausnahme, nicht der Normalfall.
- **„Der Test sagt offen, obwohl ich nichts freigegeben habe."** Dann läuft auf
  dem Port ein Dienst, oder dein Router hat per UPnP selbst freigegeben. Das ist
  ein Fund, kein Fehler — und ein guter Grund, im Router nachzusehen.
- **Meldungen von Virenscannern zu `powershell.exe`.** Das Werkzeug öffnet
  Sockets und ruft Webdienste auf; manche Scanner sind da nervös. Der Quelltext
  liegt vollständig bei und lässt sich Zeile für Zeile prüfen.
