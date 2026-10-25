# Sandy

<img src="Resources/AppIcon.png" alt="Sandy" width="160">

[English](README.md) · [Русский](README.ru.md) · [Қазақша](README.kk.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Español](README.es.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md)

Ausführliche Einrichtung: [English](README.md) · [Русский](README.ru.md).
Der Zugriff per Smartphone ist noch geplant. Sandy basiert auf dem MIT-lizenzierten
[Cyclop](https://github.com/akalikbergenov/cyclop).

Eine native macOS-App, die die Notch des MacBook in einen Arbeitsbereich verwandelt.
Bewege den Zeiger zur Notch, um Mediensteuerung, Dateiablage, Zwischenablageverlauf,
Textbausteine, Kalender, Übersetzung, Währungsumrechnung, Teleprompter und Notizen zu öffnen.

Der Tab **Agenten** überwacht unterstützte Claude-Code- und Codex-Sitzungen über den
lokalen Helfer `sandy-agent`. Er zeigt gleichzeitige Sitzungen, aktuelle Aktionen
und gespeicherte Statistiken pro Projekt. Mitteilungen zu fertigen Antworten,
erforderlichen Eingaben und Fehlern sind optional. Aktiviere die Überwachung und
die Quellen in den Einstellungen; Claude-Hooks werden nur über die eigene
Schaltfläche installiert. Einrichtung und Grenzen:
[Agentenüberwachung](docs/agent-monitor.md) (Russisch).

Sandy wird von Abdirakhym gepflegt. Das Projekt beginnt mit Version **0.1.0**
und einer eigenen Git-Historie. Angaben zu verwendetem Code Dritter stehen in
`THIRD_PARTY_NOTICES.md`.

## Sprachen

Die Oberfläche unterstützt Englisch, Russisch, Kasachisch, Deutsch, Französisch,
Spanisch, vereinfachtes Chinesisch und Japanisch. Wähle unter Einstellungen → Allgemein →
Sprache eine Sprache; das Panel wechselt sofort. „Systemsprache“ folgt der
Sprachwahl von macOS. Systemdialoge für Berechtigungen wechseln nach einem Neustart von Sandy.
Die Oberflächensprache ändert nicht das Sprachpaar im Tab „Übersetzen“.

## Tastenkürzel

Mit **Control + Option + Leertaste** öffnest du das Panel auf dem Bildschirm unter
dem Zeiger. Das Kürzel erneut drücken, Esc oder ein Klick in eine andere App
schließt es. Bei Tastaturbedienung bleibt es geöffnet. Unter Einstellungen →
Allgemein kannst du ein anderes Kürzel wählen oder die Funktion deaktivieren.
Dafür ist keine Bedienungshilfen-Berechtigung nötig.

## Erstellen und starten

Benötigt macOS 15 oder neuer und Swift 6. Die Xcode Command Line Tools reichen aus.
Führe im Projektverzeichnis Folgendes aus:

```sh
./Scripts/bundle.sh
open build/Sandy.app
```

Der lokale Build wird ad hoc signiert. Für eine mit Developer ID signierte und
von Apple notarierte Veröffentlichung benötigst du eigene Apple-Developer-Zugangsdaten;
siehe [Signierung](docs/signing.md) (Russisch).

```sh
./Scripts/test.sh        # Tests und Übersetzungen prüfen
./Scripts/test-helper.sh # Medienhelfer nach dem Build prüfen
./Scripts/dmg.sh         # build/Sandy-0.1.0.dmg erstellen
```

Die Version steht in `Scripts/version`. Konfiguriere dein eigenes Remote-Repository,
bevor du `Scripts/release.sh` verwendest.

## Daten und Berechtigungen

- App-Kennung: `com.abdirakhym.sandy`.
- Einstellungen, Textbausteine und Notizen: `~/Library/Application Support/Sandy`.
- Bildschirmfotos aus der Zwischenablage: `~/Pictures/Sandy`.
- Kalender und Tastatursperre fragen erst bei Verwendung der jeweiligen Funktion
  nach Kalenderzugriff bzw. der Bedienungshilfen-Berechtigung.
- Die Berechtigung für Agentenmitteilungen wird erst beim Aktivieren angefragt.
  Der Verlauf liegt in `~/Library/Application Support/Sandy/Agents/history.json`;
  die Überwachungsoberfläche speichert keine Prompts oder Antworten.
- Übersetzungen nutzen das macOS Translation.framework und heruntergeladene Sprachpakete.
- Die Währungsumrechnung lädt öffentliche Wechselkurse. Der Spotify-Ersatzweg kann
  Coverbilder herunterladen. Agentenstatistiken bleiben auf diesem Mac; es gibt
  keine Telemetrie und keinen automatischen Aktualisierungsdienst.

Sandy speichert eigene Einstellungen und Daten. Vorhandene Daten einer anderen
App werden nicht automatisch importiert. Details: [SECURITY.md](SECURITY.md) (Russisch).

## Entwicklung

SwiftUI- und AppKit-Code liegt in `Sources/Sandy`, der Medienhelfer in
`Sources/SandyMediaHelper`. Übersetzungen und Symbol liegen in `Resources`,
Build- und Verpackungsskripte in `Scripts`.

Lies vor Verhaltensänderungen die [Architektur](docs/architecture.md) (Englisch),
die [Beitragsregeln](CONTRIBUTING.md) und die [Release-Checkliste](docs/release-checklist.md)
(Russisch). Now Playing verwendet ein privates macOS-Framework und einen
systemeigenen Perl-Helfer. Künftige macOS-Versionen können Anpassungen erfordern.
Die App eignet sich nicht für den Vertrieb über den App Store.

## Lizenz

[MIT](LICENSE). Bewahre bei der Weitergabe von Quellcode und App die Lizenz und
die Hinweise zu Code Dritter auf. Die Begleitdateien des Bundles liegen unter
`Sandy.app/Contents/Resources`.
