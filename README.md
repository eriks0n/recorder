# Recorder

Native macOS-Menüleisten-App für lokale Meetingaufnahmen und Transkription auf Apple Silicon.

Basis: [tobi/recorder](https://github.com/tobi/recorder), erweitert mit dem [Fork von cjonesde](https://github.com/cjonesde/recorder) bei Commit `f1ba832`. Die genehmigte Umstellung auf WhisperKit ersetzt Parakeet/FluidAudio. Herkunft und Abweichungen stehen in [docs/fork-review.md](docs/fork-review.md).

## Stand

Die vollständige App wurde auf diesem Mac mit Xcode 27.1 und Apples Metal Toolchain gebaut und signiert. WhisperKit/SpeakerKit sowie die lokale MLX-Zusammenfassung sind integriert. Das bereits installierte Qwen3-4B-4bit-Modell wurde anhand eines künstlichen deutschen Meetings getestet: beide ausdrücklichen Aufgaben, gültige Belege und die genannte Frist wurden korrekt ausgegeben; eine fehlende Frist blieb leer.

Prüfstand: **131 XCTest-Tests ohne Fehler, davon 12 bewusst ausgelassene Geräte-/Aufnahmetests**, sowie **56 zusätzliche Kernprüfungen**. Das ersetzt weiterhin nicht die Langlauf- und Qualitätsabnahme mit echten Meetings oder den Vergleich mehrerer LLM-Größen.

## Bauen und starten

```sh
./build.sh
open ./Recorder.app
```

Der normale Build enthält jetzt lokale Zusammenfassungen. Das Skript bevorzugt das installierte Xcode, prüft den Metal-Compiler, bündelt die SwiftPM-/GPU-Ressourcen und signiert die App lokal. Eine reine Transkriptionsvariante ist ausdrücklich mit `RECORDER_WITH_MLX=0 ./build.sh` möglich.

MLX Swift LM ist auf 2.29.3, WhisperKit auf 1.1.0 festgelegt; die genauen Abhängigkeiten stehen in `Package.resolved`. Benötigt werden vollständiges Xcode und die Metal Toolchain. Abhängigkeiten benötigen beim ersten Build Netzwerkzugriff. Die App enthält keinen Server, keine Python-Laufzeit und keinen Cloud-Transkriptionsadapter. Sie ist nicht sandboxed und ad-hoc signiert; macOS-Berechtigungen gelten weiterhin.

## Bedienung

1. App starten, Menüleistensymbol anklicken. Mikrofon, Systemaudio, Kalender und Mitteilungen werden über macOS freigegeben. Eine Aufnahme beginnt nur durch die Aufnahmesteuerung.
2. **Settings → Local**: ausgewähltes Whisper-Modell und Sprechertrennung herunterladen. Downloads sind ausdrücklich zu starten. Fehlende oder beschädigte Modelle führen zu einer Meldung, nicht zu Cloud-Nutzung.
3. Optional vor der Aufnahme einen **Meetingnamen** eingeben. Ohne eigenen Namen wird der Kalendertitel übernommen. Bestehende Aufnahmen lassen sich über **Recent recordings → ⋯ → Meeting umbenennen…** ändern. Der neue Name wird dauerhaft in der Liste und im Transkript gespeichert; vorhandene Zusammenfassungen bleiben nutzbar, die Ordnerpfade stabil.
4. Kundenbereich vor der Aufnahme festlegen. Ein Vorschlag aus Kalenderdomains muss bestätigt werden. Ohne Zuordnung gilt der isolierte Bereich `default`.
5. **Record**, bei Bedarf **Pause**, dann **Save**. Für V1 den Standardmodus mit Audio und anschließendem Offline-Durchlauf verwenden. Desktop bleibt links, Mikrofon rechts. Während Pausen wird Stille geschrieben, damit die Zeitachsen zusammenbleiben.
6. Beide Kanäle werden separat transkribiert und bei verfügbarem SpeakerKit-Modell diarisiert. Ein stiller Desktopkanal wird übersprungen; reine Mikrofonaufnahmen benötigen keinen Kalendertermin und keine Lautsprecherausgabe. Fehlt die optionale Sprechertrennung oder schlägt sie fehl, wird der Text mit unbekannten Sprechern und einem Hinweis gespeichert. Es werden dabei keine Stimmprofile angelegt. Kanäle gelten niemals als Personen. Wortzeitstempel werden Sprecherintervallen zugeordnet; Überlappungen bleiben markiert. Live-Transkription aus dem Fork ist optional und standardmäßig aus; ihre Kanalhinweise sind keine Personenidentifikation.
7. Sprecher anklicken: Referenz anhören und nur für dieses Meeting benennen. Externe Personen ausschließlich so benennen. Ein eigenes/internes Stimmprofil erfordert die gesonderte Auswahl im Sprecher-Popover; die Einwilligung der Person sollte vorliegen. **Settings → Speakers** aktiviert die Vorbereitung von Referenzen vor der Verarbeitung. Unbestätigte Referenzen bleiben im RAM und gehen bei Neustart verloren.
8. Profile sind nach Kundenbereich, Kategorie und Embedding-Version getrennt. Mit Kalendertermin kommen neben der eigenen Stimme nur interne Profile mit passender Teilnehmer-E-Mail infrage; ohne Termin nur eigene/interne Profile desselben Bereichs. Namensvorschläge sind zusätzlich bis zur eigenen Kalibrierung deaktiviert. Vorschläge stets bestätigen oder ablehnen.
9. Das Zusammenfassungsmodell unter **Local** herunterladen. Deutsch/Englisch und automatische Erstellung sind einstellbar; manuelles Erstellen und Öffnen sind im Transkriptbereich verfügbar. Zuständige, Fristen und Belege werden validiert; gesprochene Anweisungen im Meeting lösen keine Aktionen aus. Die vier Abschnitte sind Executive Summary, Themen, Action Items und nächste Schritte.
10. Bestehende Aufnahmen lassen sich über die Bibliothek erneut verarbeiten. Alte Markdown-Transkripte bleiben als Dateien lesbar. Strukturierte Transkripte lassen sich zur Namensbearbeitung wieder laden.

## Automatische Aufbewahrung

Unter **Settings → Local → Aufbewahrung** lässt sich festlegen, nach wie vielen Tagen alte Aufnahmedateien gelöscht werden. Die Funktion ist standardmäßig **aus**; als einstellbarer Anfangswert sind 30 Tage hinterlegt.

Nach Aktivierung prüft die App beim Start und danach stündlich, solange sie läuft. Bei abgelaufenen Aufnahmen bleiben nur `transcript.md`, `transcript.json`, `summary.md` und `summary.json` erhalten, soweit vorhanden. Die JSON-Dateien enthalten die strukturierten Textdaten für spätere Bearbeitung. Audio, Rohaufnahmen, Metadaten-Dateien und alte Ergebnisgenerationen werden endgültig gelöscht. Zuerst werden die aktuellen Texte vollständig gesichert und geprüft; danach werden die übrigen Dateien entfernt. Aktive Aufnahmen und laufende Verarbeitung werden nicht unterbrochen. Aufnahmen ohne fertiges Transkript, unvollständige Ergebnisse und unsichere Verknüpfungen werden übersprungen. Die Bereinigung betrifft die konfigurierte Bibliothek und die bisherige Bibliothek unter Documents/Recordings, keine separat gespeicherten Stimmprofile.

**Jetzt bereinigen…** zeigt vor einer manuellen Bereinigung eine Bestätigung. Beim Entwickeln und Testen wurde diese Funktion ausschließlich mit temporären Testdateien ausgeführt; vorhandene Benutzeraufnahmen wurden nicht bereinigt.

## Dateien und Datenschutz

Neue Aufnahmen liegen standardmäßig unter `~/Library/Application Support/Recorder/Recordings`. Ein anderer Ordner kann unter **Local** gewählt werden. Bei erkannten Cloud-/Synchronisationspfaden erscheint ein Hinweis. Auch die bisherige Bibliothek unter `~/Documents/Recordings` wird angezeigt; alte Dateien werden nicht verschoben.

- `desktop.caf`, `mic.caf`: rohe Quellen, bleiben bis zu einer bewusst aktivierten Bereinigung zur Wiederherstellung erhalten.
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
# Gesamte XCTest-Suite (Geräte-/Modelltests standardmäßig aus):
./scripts/test.sh -c release
# Zusätzlich das installierte lokale LLM an einem künstlichen Meeting prüfen:
RECORDER_TEST_LLM=1 ./scripts/test.sh -c release --filter MeetingSummaryIntegrationTests
```

Aktueller Prüfstand: **131 XCTest-Tests ohne Fehler (12 ausgelassen)** und **56 Kernprüfungen bestanden**; vollständige MLX-Release-App gebaut und Signatur geprüft.

Die eigenständig ausführbaren Kernprüfungen brauchen weder Modelle noch Mikrofonzugriff. Sie prüfen Bereichs-/Kalender-/Modellfilter, Mehrdeutigkeit, Enrollment, Dateirechte, Belege, Zusammenfassungsgültigkeit, atomare Veröffentlichung, Abbruch und Audiokonvertierung mit synthetischen Testtönen. Die geerbten XCTest-Tests sind im Repository erhalten. Tests mit echten Geräten/Modellen sind opt-in und verwenden die in den Testdateien dokumentierten Umgebungsvariablen. Die ausgelassenen Geräte-/Aufnahmefälle werden hier nicht als bestanden gewertet.

## Offene Abnahme

- Mindestens zwei lokale LLM-Größen auf einem echten deutschen Transkript vergleichen; Qwen3-4B-4bit ist vorläufig, kein gemessener Gewinner.
- Modelle herunterladen und echte deutsche/englische Aufnahmen verarbeiten; WER, Sprecherfehler, False Matches, Latenz und Spitzen-RAM messen.
- Enrollment und Wiedererkennung auf getrennten Aufnahmen kalibrieren.
- 60–90-Minuten-Lauf, Pause/Fortsetzen, Gerätewechsel und Lautsprecherbetrieb prüfen. Abbruch erfolgt kooperativ; laufende Modelloperationen können bis zum nächsten Abbruchpunkt weiterlaufen.
- Netzwerkfreiheit während der Verarbeitung nach dem Modelldownload zusätzlich im Laufzeitversuch nachweisen.

Kein Push, keine Veröffentlichung und kein Beginn von V2. Siehe [Implementierungsplan](docs/implementation-plan.md), [Sicherheitsprüfung](docs/security-review.md) und [Modellherkunft](docs/model-provenance.md).

## Lizenz

[MIT](LICENSE). Übernommener WhisperKit-Tokenizeradapter: [Original-Lizenz](docs/third-party/WhisperKit-LICENSE). Modelllizenzen und Attributionen stehen in [docs/model-provenance.md](docs/model-provenance.md).
