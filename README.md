# Recorder

Native macOS-Menüleisten-App für lokale Meetingaufnahmen und Transkription auf Apple Silicon.

Basis: [tobi/recorder](https://github.com/tobi/recorder), erweitert mit dem [Fork von cjonesde](https://github.com/cjonesde/recorder) bei Commit `f1ba832`. Die genehmigte Umstellung auf WhisperKit ersetzt Parakeet/FluidAudio. Herkunft und Abweichungen stehen in [docs/fork-review.md](docs/fork-review.md).

## Stand

Die vollständige App wurde auf diesem Mac mit Xcode 27.1 und Apples Metal Toolchain gebaut und signiert. WhisperKit/SpeakerKit sowie die lokale MLX-Zusammenfassung sind integriert. Das bereits installierte Qwen3-4B-4bit-Modell wurde anhand eines künstlichen deutschen Meetings getestet: beide ausdrücklichen Aufgaben, gültige Belege und die genannte Frist wurden korrekt ausgegeben; eine fehlende Frist blieb leer.

Prüfstand: letzter vollständiger Lauf **210 XCTest-Tests, davon zwölf bewusst ausgelassen, ohne Fehler**, einschließlich echter lokaler Whisper-/LLM-Durchläufe mit synthetischen Daten. Außerdem **56 Kernprüfungen** und **13 Secret-Schutztests** bestanden. Das ersetzt weiterhin nicht die Langlauf- und Qualitätsabnahme mit echten Meetings oder den Vergleich mehrerer LLM-Größen.

Dokumentationsstand: **26. Oktober 2026**, Entwicklungsbranch **`codex/meeting-task-inbox`**. Der Standardbranch `main` enthält noch die frühere Gemini-Version. Diese Anleitung beschreibt den Entwicklungsbranch.

## Bauen und starten

```sh
./build.sh
open ./Recorder.app
```

Der normale Build enthält jetzt lokale Zusammenfassungen. Das Skript bevorzugt das installierte Xcode, prüft den Metal-Compiler, bündelt die SwiftPM-/GPU-Ressourcen und signiert die App lokal. Eine reine Transkriptionsvariante ist ausdrücklich mit `RECORDER_WITH_MLX=0 ./build.sh` möglich.

MLX Swift LM ist auf 2.29.3, WhisperKit auf 1.1.0 festgelegt; die genauen Abhängigkeiten stehen in `Package.resolved`. Benötigt werden vollständiges Xcode und die Metal Toolchain. Abhängigkeiten benötigen beim ersten Build Netzwerkzugriff. Die App enthält keinen Server, keine Python-Laufzeit und keinen Cloud-Transkriptionsadapter. Sie ist nicht sandboxed und ad-hoc signiert; macOS-Berechtigungen gelten weiterhin.

## Bedienung

1. App starten, Menüleistensymbol anklicken. Mikrofon, Systemaudio, Kalender und Mitteilungen werden über macOS freigegeben. Eine Aufnahme beginnt nur durch die Aufnahmesteuerung.
2. **Settings → Local**: ausgewähltes Whisper-Modell herunterladen; Sprechertrennung nur bei aktiviertem Speaker Fingerprinting erforderlich. Downloads sind ausdrücklich zu starten. Fehlende oder beschädigte Modelle führen zu einer Meldung, nicht zu Cloud-Nutzung.
3. Optional vor der Aufnahme einen **Meetingnamen** eingeben. Ohne eigenen Namen wird der Kalendertitel übernommen. Bestehende Aufnahmen lassen sich über **Recent recordings → ⋯ → Meeting umbenennen…** ändern. Der neue Name wird dauerhaft in der Liste und im Transkript gespeichert; vorhandene Zusammenfassungen bleiben nutzbar, die Ordnerpfade stabil.
4. Kundenbereich vor der Aufnahme festlegen. Ein Vorschlag aus Kalenderdomains muss bestätigt werden. Ohne Zuordnung gilt der isolierte Bereich `default`.
5. **Record**, bei Bedarf **Pause**, dann **Save**. Für V1 den Standardmodus mit Audio und anschließendem Offline-Durchlauf verwenden. Desktop bleibt links, Mikrofon rechts. Während Pausen wird Stille geschrieben, damit die Zeitachsen zusammenbleiben.
6. Beide Kanäle werden separat transkribiert. Ein stiller Desktopkanal wird übersprungen; reine Mikrofonaufnahmen benötigen keinen Kalendertermin und keine Lautsprecherausgabe. Bei aktiviertem **Speaker Fingerprinting** werden Sprecher mit SpeakerKit getrennt. Fehlt dieses Modell oder schlägt die Analyse fehl, bleibt die Transkription verfügbar. Kanäle gelten niemals als Personen. Live-Transkription ist optional und standardmäßig aus; Kanalhinweise identifizieren keine Personen.
7. **Settings → Speakers → Speaker Fingerprinting** schaltet Stimmanalyse, Profilvergleich und das Speichern neuer Stimmprofile gemeinsam ein oder aus. Standardmäßig aus. Ausgeschaltet werden gespeicherte Profile nicht geladen oder benutzt; laufende Analyseergebnisse werden verworfen. Bereits gespeicherte Profile bleiben erhalten und lassen sich gesondert löschen. Sprecher können weiterhin nur für das jeweilige Meeting benannt werden.
8. Bei aktiviertem Fingerprinting lassen sich saubere Referenzabschnitte nach ausdrücklicher Auswahl als Stimmprofil speichern; die Einwilligung der Person sollte vorliegen. Profile werden innerhalb desselben Kundenbereichs und derselben Modellversion verglichen. Es gibt keine Unterscheidung zwischen intern und extern und keine Beschränkung auf Kalenderteilnehmer. Namensvorschläge stets bestätigen oder ablehnen. Unbestätigte Referenzen bleiben im RAM und gehen bei Neustart verloren.
9. Das Zusammenfassungsmodell unter **Local** herunterladen. Deutsch/Englisch und automatische Erstellung sind einstellbar; manuelles Erstellen und Öffnen sind im Transkriptbereich verfügbar. Zuständige, Fristen und Belege werden validiert; gesprochene Anweisungen im Meeting lösen keine Aktionen aus. Die vier Abschnitte sind Executive Summary, Themen, Action Items und nächste Schritte.
10. Bestehende Aufnahmen lassen sich über die Bibliothek erneut verarbeiten. Alte Markdown-Transkripte bleiben als Dateien lesbar. Strukturierte Transkripte lassen sich zur Namensbearbeitung wieder laden.

## Eigene Begriffe, Template und Mikrofon

- **Settings → Transcription**: Namen, Marken und Fachbegriffe zeilenweise pflegen. Die Liste unterstützt die Erkennung; sie ersetzt Wörter nicht pauschal und garantiert keine Fehlerfreiheit. Amin und Armin bei Bedarf beide eintragen.
- **Settings → Local → Markdown-Template**: eigenes Layout mit Platzhaltern bearbeiten und speichern. „Standard einsetzen“ zeigt ein Beispiel. Die belegten Aufgaben bleiben unabhängig vom Layout für Todoist erhalten.
- **Settings → Recording → Mikrofon**: Systemstandard oder ein bestimmtes Mikrofon für die nächste Aufnahme wählen. Eine fehlende feste Quelle verhindert den Start mit einer Meldung.

Kein festes Minutenlimit. Für lange Aufnahmen begrenzen freier Speicher, RAM und lokale Verarbeitungszeit. 30–60 Minuten sind der vorgesehene Einsatzbereich; für zwei bis vier Stunden sind neue Aufnahmen an Pausen aktuell sinnvoll. Pause schreibt Stille und spart keinen Audiospeicher. Details, Speicherabschätzungen und offene Langlaufabnahme: [Anpassungen und Aufnahmedauer](docs/meeting-customization.md).

## Sprecher später zuordnen

Unter **Recent recordings → ⋯ → Transkript und Sprecher bearbeiten** eine gespeicherte Aufnahme öffnen und den Sprecher anklicken. Meetingbezogene Namen lassen sich auch nach Neustart und nach dem Löschen des Audios ändern. Anschließend die Zusammenfassung erneuern, damit die Aufgaben die aktuelle Zuordnung verwenden.

Das Speichern eines dauerhaften Stimmprofils benötigt geeignete unbestätigte Stimmreferenzen. Diese bleiben nur im Arbeitsspeicher, bis Recorder beendet, Fingerprinting ausgeschaltet oder die Stimmreferenzen gelöscht werden. Danach ist ein erneuter Durchlauf mit aktiviertem Fingerprinting und noch vorhandenem Audio erforderlich. Zum späteren Anhören oder Anlegen von Stimmprofilen Audio zunächst aufbewahren.

## Automatische Aufbewahrung

Unter **Settings → Local → Aufbewahrung** gibt es zwei unabhängige, standardmäßig ausgeschaltete Optionen.

**Audio direkt nach Transkription und Zusammenfassung löschen** erstellt automatisch auch die lokale Zusammenfassung. Erst wenn beide vollständigen Texte erfolgreich gespeichert und geprüft sind, werden Audiodateien der Aufnahme gelöscht. Auch im Modus „Audio kept“ wird dafür ein vollständiger Offline-Durchlauf durchgeführt. Bei Fehlern, fehlendem Modell oder Abbruch bleibt das Audio zur Wiederherstellung erhalten. Transkript, Zusammenfassung und andere Anhänge bleiben bestehen. Ohne Audio ist eine erneute Transkription nicht mehr möglich; die Zusammenfassung lässt sich aus dem vorhandenen Text weiter erstellen.

Mit **Alte Aufnahmedateien automatisch löschen** lässt sich zusätzlich festlegen, nach wie vielen Tagen alte Aufnahmedateien gelöscht werden. Die Funktion ist standardmäßig **aus**; als einstellbarer Anfangswert sind 30 Tage hinterlegt.

Nach Aktivierung prüft die App beim Start und danach stündlich, solange sie läuft. Bei abgelaufenen Aufnahmen bleiben nur `transcript.md`, `transcript.json`, `summary.md` und `summary.json` erhalten, soweit vorhanden. Die JSON-Dateien enthalten die strukturierten Textdaten für spätere Bearbeitung. Audio, Rohaufnahmen, Metadaten-Dateien und alte Ergebnisgenerationen werden endgültig gelöscht. Zuerst werden die aktuellen Texte vollständig gesichert und geprüft; danach werden die übrigen Dateien entfernt. Aktive Aufnahmen und laufende Verarbeitung werden nicht unterbrochen. Auch wartende oder fehlerhafte Verarbeitungsaufträge sperren die Bereinigung, bis sie abgeschlossen oder verworfen sind. Aufnahmen ohne fertiges Transkript, unvollständige Ergebnisse und unsichere Verknüpfungen werden übersprungen. Die Bereinigung betrifft die konfigurierte Bibliothek und die bisherige Bibliothek unter Documents/Recordings, keine separat gespeicherten Stimmprofile.

**Jetzt bereinigen…** zeigt vor einer manuellen Bereinigung eine Bestätigung. Beim Entwickeln und Testen wurde diese Funktion ausschließlich mit temporären Testdateien ausgeführt; vorhandene Benutzeraufnahmen wurden nicht bereinigt.

## Aufgaben-Inbox und Todoist

Aufnahmen werden nach dem Speichern in einer dauerhaften Warteschlange verarbeitet. Neue Aufnahmen haben Vorrang; unterbrochene Aufträge werden später fortgesetzt und überleben einen Neustart. Fehler und Wiederholen stehen unter **Settings → Local → Verarbeitung**.

**Aufgaben-Inbox öffnen…** sammelt Aufgaben aus allen gespeicherten Zusammenfassungen. Ein Meeting wählen, über **Ich bin im Meeting…** den eigenen Sprecher bestimmen und **# Projekt / @ Tags** gemeinsam für alle offenen Aufgaben übernehmen. Zuständigkeit, Belege und Termine je Aufgabe prüfen und **Prüfen und für Todoist auswählen** anklicken. Anschließend ausschließlich eigene, ausgewählte Aufgaben dieses Meetings als Todoist-CSV exportieren oder mit **Mit Todoist synchronisieren…** direkt übertragen. Eine spätere Sprecherkorrektur verlangt erneute Prüfung; eigene Aufgabentitel bleiben erhalten. Termine werden aus dem Meetingdatum vorgeschlagen.

Für direkte Übertragung unter **Settings → Todoist** den persönlichen API-Key in das umrandete Passwortfeld eingeben (tippen, **Einfügen** oder ⌘V) und mit **Verbindung prüfen und sicher speichern** im macOS-Schlüsselbund hinterlegen. Erst die ausdrücklich gewählten Aufgaben mit kurzen Belegen verlassen den Mac; Audio und vollständige Transkripte bleiben lokal. CSV funktioniert ohne Verbindung. Exportstatus und feste Auftragsnummern schützen vor unbeabsichtigten Wiederholungen. Eine CSV nur einmal importieren.

Aktuelle Bedienung und Fehlerfälle: [Todoist je Meeting](docs/meeting-todoist-sync.md). Speicherorte und technische Grundlagen: [Aufgaben-Inbox und Todoist](docs/task-inbox-todoist.md).

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

## Schutz vor versehentlich veröffentlichten Secrets

Die `.gitignore` schließt alle `.env`-Varianten (auch verschachtelt und Beispiele), Credential-Dateien, private Schlüssel/Zertifikate und private Laufzeitdaten aus. Ein zusätzliches Dateiverbot erkennt solche Pfade auch bei `git add -f`. Gitleaks prüft die Inhalte auf bekannte Schlüssel- und Secret-Muster.

Für **jeden neuen Clone** einmal aktivieren:

```sh
./scripts/setup-security.sh
```

Das installiert Gitleaks 8.30.1 mit festgelegter SHA-256-Prüfsumme in den ignorierten Build-Ordner und installiert die versionierten Schutzprüfungen zusätzlich im lokalen Git-Verzeichnis. Dadurch bleiben sie bei Branchwechseln und nach einer Bereinigung von `.build` aktiv. Ein vorhandener anderer Hooks-Pfad wird nicht überschrieben. Nach Änderungen an den Schutzskripten das Setup erneut ausführen, um die lokal installierte Kopie zu aktualisieren. Vor Commits werden die vorgemerkten Dateien geprüft; vor Pushes die gesamte erreichbare Historie einschließlich ausdrücklich gepushter Commit-IDs. Fehlender Scanner und Scannerfehler blockieren den Vorgang. Ein blockierter Commit verändert oder löscht keine privaten Dateien.

Zusätzlich prüft der GitHub-Workflow **Secret protection** Pushes und Pull Requests mit derselben Policy. Der Scanner gibt keine Secret-Werte aus; rohe Fundberichte werden nicht veröffentlicht. Der Workflow verwendet ausschließlich Leserechte und einen auf einen Commit festgelegten Checkout-Schritt.

Manuell prüfen:

```sh
python3 scripts/test-secret-protection.py
python3 scripts/check-secrets.py staged
python3 scripts/check-secrets.py history
```

Bewusstes Umgehen lokaler Hooks (`--no-verify`), Änderungen der Schutzskripte oder bislang unbekannte Secret-Formate lassen sich dadurch nicht absolut ausschließen. GitHub-CI erkennt Probleme erst nach dem Push; für verbindliche Merge-Sperren muss **Secret protection / scan** zusätzlich als erforderliche Prüfung in den Branch-Regeln hinterlegt sein. Bereits versionierte Secrets werden durch `.gitignore` nicht rückwirkend entfernt und müssten separat gesperrt und aus der Historie bereinigt werden.

## Prüfungen

```sh
./scripts/check-core.sh
# Gesamte XCTest-Suite (Geräte-/Modelltests standardmäßig aus):
./scripts/test.sh -c release
# Zusätzlich das installierte lokale LLM an einem künstlichen Meeting prüfen:
RECORDER_TEST_LLM=1 ./scripts/test.sh -c release --filter MeetingSummaryIntegrationTests
```

Nachweise nach Änderung getrennt, damit gezielte Nachprüfungen nicht als neuer vollständiger Lauf gezählt werden:

| Prüfung | Letzter nachgewiesener Stand |
| --- | --- |
| Vollständige XCTest-Suite mit lokalem LLM | 210 Tests, 12 Geräte-/Aufnahmefälle ausgelassen, 0 Fehler; lokales LLM und Whisper mit synthetischen Daten |
| API-Key-Eingabe und Todoist nach UI-Korrektur | 34 Tests, einschließlich 4 neuer UI-Tests, 0 Fehler |
| Unabhängige Kernprüfungen | 56 bestanden |
| Commit-/Push-Schutz | 13 Tests bestanden; GitHub-Workflow erfolgreich |
| App-Build | Vollständige MLX-App gebaut, Signatur geprüft |

Der aktuelle vollständige Lauf umfasst alle 210 XCTest-Fälle. Die zwölf übersprungenen Geräte-/Aufnahmefälle bleiben offen.

Die eigenständig ausführbaren Kernprüfungen brauchen weder Modelle noch Mikrofonzugriff. Sie prüfen Bereichs-/Modellfilter, Mehrdeutigkeit, Enrollment, Dateirechte, Belege, Zusammenfassungsgültigkeit, atomare Veröffentlichung, Abbruch und Audiokonvertierung mit synthetischen Testtönen. Die geerbten XCTest-Tests sind im Repository erhalten. Tests mit echten Geräten/Modellen sind opt-in und verwenden die in den Testdateien dokumentierten Umgebungsvariablen. Die ausgelassenen Geräte-/Aufnahmefälle werden hier nicht als bestanden gewertet.

## Offene Abnahme

- Mindestens zwei lokale LLM-Größen auf einem echten deutschen Transkript vergleichen; Qwen3-4B-4bit ist vorläufig, kein gemessener Gewinner.
- Modelle herunterladen und echte deutsche/englische Aufnahmen verarbeiten; WER, Sprecherfehler, False Matches, Latenz und Spitzen-RAM messen.
- Enrollment und Wiedererkennung auf getrennten Aufnahmen kalibrieren.
- 60–90-Minuten-Lauf, Pause/Fortsetzen, Gerätewechsel und Lautsprecherbetrieb prüfen. Abbruch erfolgt kooperativ; laufende Modelloperationen können bis zum nächsten Abbruchpunkt weiterlaufen.
- Netzwerkfreiheit während der Verarbeitung nach dem Modelldownload zusätzlich im Laufzeitversuch nachweisen.

Der bisherige Stand wurde auf den Entwicklungsbranch gepusht; die Aufgaben-Inbox/Todoist-Erweiterung wurde anschließend ausdrücklich beauftragt. Keine Veröffentlichung einer Release-Version. Siehe [Implementierungsplan](docs/implementation-plan.md), [Sicherheitsprüfung](docs/security-review.md) und [Modellherkunft](docs/model-provenance.md).

## Lizenz

[MIT](LICENSE). Übernommener WhisperKit-Tokenizeradapter: [Original-Lizenz](docs/third-party/WhisperKit-LICENSE). Modelllizenzen und Attributionen stehen in [docs/model-provenance.md](docs/model-provenance.md).
