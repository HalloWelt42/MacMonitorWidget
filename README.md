<p align="center"><img src="docs/icon.png" width="160" alt="Leitwarte"></p>

# Leitwarte

Ein nativer Systemmonitor für macOS - als Menüleisten-Programm und als
Schreibtisch-Widget. Leitwarte zeigt CPU-, RAM-, GPU-, Energieverbrauch und
Temperatur in frei zusammenstellbaren Anzeige-Bausteinen: Du wählst aus, welche
Bausteine in welcher Reihenfolge erscheinen und welche Messwerte jeder zeigt.

## Bausteine

- **Ringe** - mehrere Werte als Ring-Messer nebeneinander, auf einen Blick
- **Balken** - Liste mit genauen Werten (Prozent, GB, Watt)
- **Verlauf** - Sparklines, die den Trend über die letzte Minute zeigen
- **Minimal** - eine Kennzahl groß, der Rest klein darunter
- **Tacho** - die mittlere Gesamtlast als Zeiger

Die Zusammenstellung lässt sich im eingebauten Konfigurator ändern: Bausteine
an- und abschalten, ihre Reihenfolge verschieben und je Baustein die Metriken
wählen. Takt (0,5 bis 10 Sekunden) und Darstellung der Menüleiste sind ebenfalls
einstellbar. Die Auswahl wird dauerhaft gesichert.

## Messwerte

Alle Werte werden lokal gelesen, ohne besondere Rechte und ohne
Berechtigungsdialoge:

- **CPU** - Auslastung gesamt und je Kern über `host_processor_info`
- **RAM** - belegter Speicher über `host_statistics64`, gerechnet wie die
  Aktivitätsanzeige (App-Speicher plus fest verdrahtet plus komprimiert)
- **GPU** - Auslastung über das IORegistry (`IOAccelerator`,
  `PerformanceStatistics`)
- **Energie** - Gesamte Systemleistung in Watt über den SMC-Sensor; zusätzlich
  CPU-, GPU- und Rechenleistung über das IOReport-System (Apple-Silicon
  "Energy Model")
- **Temperatur** - über IOHID-Sensoren (Mittel der Die-Sensoren)
- **Lüfter** - Drehzahl über SMC (`F<n>Ac`); steht im Leerlauf still
- **Swap** - Auslagerungsdatei über `sysctl vm.swapusage`
- **Takt** - mittlerer Takt und Auslastung je CPU-Cluster und GPU über die
  IOReport-Verweildauern je Taktstufe
- **Neural Engine** - Leistung in Watt über IOReport

## Schreibtisch-Widget

Neben dem Menüleisten-Programm gibt es ein echtes Schreibtisch-Widget (klein,
mittel, groß), das du wie jedes andere Widget aus der Galerie hinzufügst
(Schreibtisch oder Mitteilungszentrale). Wichtig zur Funktionsweise:

- Das Betriebssystem aktualisiert Widgets in eigenem Takt (wie beim Wetter),
  nicht sekündlich.
- Widgets laufen verpflichtend in der Sandbox und dürfen dort nur CPU und RAM
  selbst messen. Die übrigen Werte (GPU, Energie, Temperatur) liefert das
  laufende Menüleisten-Programm über eine geteilte App-Gruppe - läuft es nicht,
  zeigt das Widget CPU und RAM.

## Chip-Übersicht (extragroßes Widget)

![Chip-Übersicht](docs/chip-widget.png)

Ein zweites Widget zeigt den Apple-Silicon-Chip im Terminal-Stil auf dem
Schreibtisch - halbtransparent in Petrol und Salbeigrün:

- **E-CPU und P-CPU** - Auslastung und mittlerer Takt je Cluster (z. B.
  `24% @ 1833 MHz`) mit Verlauf. Die Auslastung ist auf den Höchsttakt
  bezogen: ein Kern, der voll, aber mit halbem Takt läuft, zählt etwa zur Hälfte.
- **GPU** - Auslastung und Takt mit Verlauf
- **RAM und Swap** - belegt und gesamt in GB, Verlauf des Arbeitsspeichers
- **Leistung** - CPU, GPU und Neural Engine in Watt mit Mittel und Höchstwert
  des Verlaufs, dazu CPU- und GPU-Temperatur, Lüfterdrehzahlen und die
  Gesamtleistung des Rechners

Takt und Auslastung stammen aus den Verweildauern je Taktstufe (IOReport
"CPU Stats" und "GPU Stats"), die Taktstufen selbst aus dem IORegistry
(`pmgr`). Die Kopfzeile nennt Chip, Kernzahlen und Speicher; unten steht, wie
alt die Werte sind. Läuft das Menüleisten-Programm nicht, meldet das Widget den
Stand der letzten Messung.

Das Widget gibt es in der Größe "Extragroß" und nur auf dem Schreibtisch (die
Mitteilungszentrale bietet diese Größe nicht an).

## Anforderungen

- macOS 14 oder neuer
- Swift 6, Xcode und XcodeGen (zum Bauen)

## Bauen und installieren

```
scripts/make_app.sh
```

Das Skript erzeugt mit XcodeGen das Projekt, baut Programm und Widget, signiert
beide mit den passenden Entitlements und installiert nach `/Applications`. Das
Menüleisten-Programm läuft ohne Dock-Symbol.

Zur kopflosen Kontrolle des Datenkerns gibt es einen Diagnosemodus:

```
.build/debug/Leitwarte --dump             # Messwerte einmalig auf der Konsole
.build/debug/Leitwarte --dump --channels  # zusätzlich alle IOReport-Kanäle und Fühler
.build/debug/Leitwarte --snapshot DIR      # Bausteine und Widgets als PNG nach DIR
```

Das Programmsymbol wird mit `swift tools/make_icon.swift` gezeichnet.

## Version

Die Version steht allein in `version.json`. Ein Pre-Commit-Hook
(`tools/git-hooks`, aktiviert mit `git config core.hooksPath tools/git-hooks`)
zählt sie bei jedem Commit hoch; das Bauskript reicht sie an Programm und
Widget weiter.

## Lizenz

Nicht-kommerzielle Lizenz v1.0 - siehe [LICENSE](LICENSE).

Das Widget bringt die Schrift JetBrains Mono mit; sie steht unter der SIL Open
Font License 1.1 ([Sources/Widget/Fonts/OFL.txt](Sources/Widget/Fonts/OFL.txt)).

## Unterstützen

Leitwarte ist ein privates Open-Source-Projekt. Kein Tracking, keine Werbung,
keine Kompromisse.

Wenn dir das Projekt gefällt, kannst du direkt hier "Danke sagen":

[![Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/HalloWelt42)

**Crypto:**

| Coin | Adresse |
|------|---------|
| BTC | `bc1qnd599khdkv3v3npmj9ufxzf6h4fzanny2acwqr` |
| DOGE | `DL7tuiYCqm3xQjMDXChdxeQxqUGMACn1ZV` |
| ETH | `0x8A28fc47bFFFA03C8f685fa0836E2dBe1CA14F27` |

Copyright (c) 2025-2026 HalloWelt42
