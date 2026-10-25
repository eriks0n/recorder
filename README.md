# Recorder

Native macOS-Menüleisten-App für lokale Meetingaufnahmen und Transkription auf Apple Silicon.

Basis: [tobi/recorder](https://github.com/tobi/recorder), erweitert mit dem [Fork von cjonesde](https://github.com/cjonesde/recorder) bei Commit `f1ba832`. Die genehmigte Umstellung auf WhisperKit ersetzt Parakeet/FluidAudio. Herkunft und Abweichungen stehen in [docs/fork-review.md](docs/fork-review.md).

## Stand

Die App lässt sich hier mit den Command Line Tools und dem macOS-26.5-SDK bauen. WhisperKit/SpeakerKit und die Oberfläche sind integriert. Die Modelle müssen einmal ausdrücklich heruntergeladen werden. Echte Meetingaufnahmen, Erkennungsqualität, Kalibrierung und 60–90-Minuten-Läufe stehen gemäß Nutzerentscheidung noch zur Abnahme aus.

Der lokale MLX-Zusammenfassungsadapter ist implementiert, aber in diesem Build deaktiviert: Auf diesem Mac fehlen vollständiges Xcode, Metal-Compiler und XCTest. Die MLX-Buildvariante und die Modellqualität sind deshalb **noch nicht verifiziert**. Ein fehlendes LLM beeinträchtigt das gespeicherte Transkript nicht.

## Bauen und starten

```sh
./build.sh
open ./Recorder.app
```

Das Skript bündelt die SwiftPM-Ressourcen und signiert die App lokal. In der hier installierten CLT-Umgebung verwendet es das funktionsfähige macOS-26.5-SDK. `RECORDER_SDK=/absoluter/pfad/zum/SDK` überschreibt die Auswahl.

Für Zusammenfassungen nach Installation von vollständigem Xcode samt Metal-Werkzeugen:

```sh
RECORDER_WITH_MLX=1 ./build.sh
```

MLX Swift LM ist auf 2.29.3, WhisperKit auf 1.1.0 festgelegt. Abhängigkeiten benötigen beim ersten Build Netzwerkzugriff. Die App enthält keinen Server, keine Python-Laufzeit und keinen Cloud-Transkriptionsadapter. Die App ist nicht sandboxed und ad-hoc signiert; macOS-Berechtigungen gelten weiterhin.

## Bedienung

1. App starten, Menüleistensymbol anklicken. Mikrofon, Systemaudio, Kalender und Mitteilungen werden über macOS freigegeben. Eine Aufnahme beginnt nur durch die Aufnahmesteuerung.
2. **Settings → Local**: ausgewähltes Whisper-Modell und Sprechertrennung herunterladen. Downloads sind ausdrücklich zu starten. Fehlende oder beschädigte Modelle führen zu einer Meldung, nicht zu Cloud-Nutzung.
3. Kundenbereich vor der Aufnahme festlegen. Ein Vorschlag aus Kalenderdomains muss bestätigt werden. Ohne Zuordnung gilt der isolierte Bereich `default`.
4. **Record**, bei Bedarf **Pause**, dann **Save**. Für V1 den Standardmodus mit Audio und anschließendem Offline-Durchlauf verwenden. Desktop bleibt links, Mikrofon rechts. Während Pausen wird Stille geschrieben, damit die Zeitachsen zusammenbleiben.
5. Beide Kanäle werden separat transkribiert und bei verfügbarem SpeakerKit-Modell diarisiert. Ein stiller Desktopkanal wird übersprungen; reine Mikrofonaufnahmen benötigen keinen Kalendertermin und keine Lautsprecherausgabe. Fehlt die optionale Sprechertrennung oder schlägt sie fehl, wird der Text mit unbekannten Sprechern und einem Hinweis gespeichert. Es werden dabei keine Stimmprofile angelegt. Kanäle gelten niemals als Personen. Wortzeitstempel werden Sprecherintervallen zugeordnet; Überlappungen bleiben markiert. Live-Transkription aus dem Fork ist optional und standardmäßig aus; ihre Kanalhinweise sind keine Personenidentifikation.
6. Sprecher anklicken: Referenz anhören und nur für dieses Meeting benennen. Externe Personen ausschließlich so benennen. Ein eigenes/internes Stimmprofil erfordert die gesonderte Auswahl im Sprecher-Popover; die Einwilligung der Person sollte vorliegen. **Settings → Speakers** aktiviert die Vorbereitung von Referenzen vor der Verarbeitung. Unbestätigte Referenzen bleiben im RAM und gehen bei Neustart verloren.
7. Profile sind nach Kundenbereich, Kategorie und Embedding-Version getrennt. Mit Kalendertermin kommen neben der eigenen Stimme nur interne Profile mit passender Teilnehmer-E-Mail infrage; ohne Termin nur eigene/interne Profile desselben Bereichs. Namensvorschläge sind zusätzlich bis zur eigenen Kalibrierung deaktiviert. Vorschläge stets bestätigen oder ablehnen.
8. Bei einem MLX-Build das Zusammenfassungsmodell unter **Local** herunterladen. Deutsch/Englisch und automatische Erstellung sind einstellbar; manuelles Erstellen und Öffnen sind im Transkriptbereich verfügbar. Zuständige, Fristen und Belege werden validiert; gesprochene Anweisungen im Meeting lösen keine Aktionen aus. Die vier Abschnitte sind Executive Summary, Themen, Action Items und nächste Schritte.
9. Bestehende Aufnahmen lassen sich über die Bibliothek erneut verarbeiten. Alte Markdown-Transkripte bleiben als Dateien lesbar. Strukturierte Transkripte lassen sich zur Namensbearbeitung wieder laden.

## Dateien und Datenschutz

Neue Aufnahmen liegen standardmäßig unter `~/Library/Application Support/Recorder/Recordings`. Ein anderer Ordner kann unter **Local** gewählt werden. Bei erkannten Cloud-/Synchronisationspfaden erscheint ein Hinweis. Auch die bisherige Bibliothek unter `~/Documents/Recordings` wird angezeigt; alte Dateien werden nicht verschoben.

- `desktop.caf`, `mic.caf`: rohe Quellen, bleiben zur Wiederherstellung erhalten.
- `audio.m4a`: blockweise erzeugter Stereomix; Veröffentlichung erst nach erfolgreichem Abschluss.
- `meeting.json`: versionierte Metadaten, Bereich und Kalenderteilnehmer.
- `transcript.json`, `transcript.md`: strukturierte Daten und lesbarer Export mit stabilen Turn-IDs.
- `Results/<UUID>/` und `current-result.json`: vollständige Generationen und atomarer Verweis auf den gültigen Stand.
- `summary.json`, `summary.md`: abgeleitete Exporte bei erfolgreicher Zusammenfassung.
- `Summaries/<UUID>/` und `current-summary.json`: vollständig veröffentlichte Zusammenfassungen. Nach Transkriptänderungen wird ein veralteter Stand nicht als aktuell geöffnet.

Modelle und bestätigte Stimmprofile liegen separat in Application Support. Neue private Verzeichnisse erhalten Rechte `0700`, private Datendateien `0600`. Die App fügt keine eigene Verschlüsselung hinzu. FileVault ist eine Betriebssystemfunktion. Keine Audiodaten oder Stimmmerkmale gehören ins Git-Repository oder in Logs. Profillöschen entfernt Stimmmerkmale; bewusst vergebene Meetingnamen bleiben Teil des Transkripts.

## Prüfungen

```sh
./scripts/check-core.sh
# Mit vollständigem Xcode:
swift test
```

Aktueller Prüfstand: **56 Kernprüfungen bestanden**, Release-App gebaut und Signatur geprüft.

Die eigenständig ausführbaren Kernprüfungen brauchen weder Modelle noch Mikrofonzugriff. Sie prüfen Bereichs-/Kalender-/Modellfilter, Mehrdeutigkeit, Enrollment, Dateirechte, Belege, Zusammenfassungsgültigkeit, atomare Veröffentlichung, Abbruch und Audiokonvertierung mit synthetischen Testtönen. Die geerbten XCTest-Tests sind im Repository erhalten. Tests mit echten Geräten/Modellen sind opt-in und verwenden die in den Testdateien dokumentierten Umgebungsvariablen. Sie wurden hier nicht als bestanden gewertet.

## Offene Abnahme

- Vollständiges Xcode installieren, XCTest ausführen und MLX-Build kompilieren/testen.
- Mindestens zwei lokale LLM-Größen auf einem echten deutschen Transkript vergleichen; Qwen3-4B-4bit ist vorläufig, kein gemessener Gewinner.
- Modelle herunterladen und echte deutsche/englische Aufnahmen verarbeiten; WER, Sprecherfehler, False Matches, Latenz und Spitzen-RAM messen.
- Enrollment und Wiedererkennung auf getrennten Aufnahmen kalibrieren.
- 60–90-Minuten-Lauf, Pause/Fortsetzen, Gerätewechsel und Lautsprecherbetrieb prüfen. Abbruch erfolgt kooperativ; laufende Modelloperationen können bis zum nächsten Abbruchpunkt weiterlaufen.
- Netzwerkfreiheit während der Verarbeitung nach dem Modelldownload zusätzlich im Laufzeitversuch nachweisen.

Kein Push, keine Veröffentlichung und kein Beginn von V2. Siehe [Implementierungsplan](docs/implementation-plan.md), [Sicherheitsprüfung](docs/security-review.md) und [Modellherkunft](docs/model-provenance.md).

## Lizenz

[MIT](LICENSE). Übernommener WhisperKit-Tokenizeradapter: [Original-Lizenz](docs/third-party/WhisperKit-LICENSE). Modelllizenzen und Attributionen stehen in [docs/model-provenance.md](docs/model-provenance.md).
