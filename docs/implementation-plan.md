# Implementierungsplan: lokaler Meeting-Recorder mit Sprecherprofilen und Zusammenfassungen

Stand: 25. Oktober 2026 · Zielplattform: Lennarts Apple-Silicon-Mac · Ausgangspunkt: https://github.com/tobi/recorder

Status: Umsetzungsplan, noch keine Implementierung. Nach dem Klonen wird der aktuelle Code geprüft und der Plan bei Bedarf angepasst. Alle Typ- und Dateinamen sind Entwurfsentscheidungen, keine Aussage über bestehende SDK-APIs.

Der Plan ist in zwei Stufen geteilt: **V1** liefert schnell ein im Alltag nutzbares Werkzeug. **V2** ergänzt Robustheit und Komfort, sobald sich V1 bewährt hat. V2 wird erst begonnen, wenn Lennart V1 abgenommen hat.

---

## Umsetzungsstand und genehmigte Abweichungen (25. Oktober 2026)

Der Nutzer hat die Tests mit echten Aufnahmen auf später verschoben und ausdrücklich die Übernahme von `cjonesde/recorder` mit WhisperKit statt Parakeet/FluidAudio genehmigt. Diese Entscheidung hat Vorrang vor den ursprünglichen Modellvorgaben. V2 bleibt außerhalb des Auftrags.

- Sicherheitsprüfung des ursprünglichen Quellstands vor Ausführung: dokumentiert in `docs/security-review.md`; keine Hinweise auf bösartigen Code gefunden, keine Garantie vollständiger Schwachstellenfreiheit.
- P0: Quellprüfung, feste Bibliotheks-/Modellrevisionen und lokaler Build erledigt. Echter Modellvergleich, Download-/RAM-Messwerte und Aufnahmeprüfung bleiben offen. CLT-Umgebung statt vollständigem Xcode; macOS-27-SDK unvollständig, macOS-26.5-SDK funktioniert. Kein vorgetäuschter P0-Pass.
- Basis: cjonesde-Fork bei f1ba832, Lizenz/Herkunft in `docs/fork-review.md`.
- P1/P2: lokale WhisperKit-/SpeakerKit-Integration; ausdrücklich gestartete Modelldownloads; Offline-Laden ohne Tokenizer-Netzwerkfallback; beide Kanäle separat diarisiert, Wortzeitstempel und Überlappungsmarker. Modellqualität noch ungemessen.
- P3: explizite interne/eigene Profile, Meetingnamen für externe Personen, Bereichs-/Kalender-/Modellfilter, Mindestabstand zum zweitbesten Treffer. Unbestätigte Referenzen nur im RAM; Namensvorschläge bleiben bis zur Kalibrierung deaktiviert.
- P4: Abbruch/erneute Verarbeitung, vollständige Ergebnisgenerationen mit atomarem Zeiger, private Dateirechte, lokaler Standardordner und Synchronisationshinweis, blockweises Audiomischen. Pausen behalten die gemeinsame Zeitachse durch Stille. Hardware-/Langlaufabnahme offen.
- P5: lokaler MLX-Adapter, Tokenbudget/Abschnitte/Konsolidierung, maximal zwei Reparaturversuche, Schema-/Beleg-/Frist-/Zuständigenprüfung, vier Exportabschnitte und separate Fehleranzeige implementiert. **MLX-Build und Inferenz sind hier noch nicht verifiziert**: Metal-Compiler fehlt. Der CLT-Build meldet diese Voraussetzung klar und behält das Transkript. Keine Cloud-Alternative.

Prüfstand: 56 ausführbare Kernprüfungen bestanden (ohne echte Meetings, mit synthetischen Testtönen); Release-App gebaut, Ressourcen gebündelt und Ad-hoc-Signatur geprüft. Der geerbte XCTest-Lauf scheitert in dieser CLT-Umgebung am fehlenden XCTest-Modul und ist ausdrücklich nicht als bestanden gewertet.

V1 ist damit als Implementierung fortgeschritten, aber noch nicht vollständig abgenommen. Insbesondere werden die ursprünglichen Qualitätsziele nicht als erreicht behauptet. Die aktuelle Bedienung und offenen Prüfschritte stehen im README.

---

## 1. Ziel

Eine native macOS-App nimmt Meetings auf, transkribiert sie lokal (Deutsch und Englisch), trennt Sprecher, erkennt bestätigte Personen in späteren Meetings wieder und erstellt eine lokale Zusammenfassung mit Aufgaben. Audio, Texte und Stimmprofile verlassen den Mac nicht. Kein eigener Server, keine Python-Laufzeit im Produkt, kein automatischer Cloud-Fallback.

Nicht Teil von V1 oder V2: iPhone-Aufnahme, Live-Transkription, eigenes Modelltraining, Notion- oder Cloud-Synchronisation, App-Store-Vertrieb.

## 2. Leitprinzipien (gelten für V1 und V2)

1. **Lokal als Standard.** Der bestehende Gemini-Adapter bleibt optional nutzbar, wird aber nie automatisch als Fallback verwendet.
2. **Namen sind Vorschläge.** Kein Sprecher wird ohne Bestätigung durch Lennart als Person geführt. Nur bestätigte, saubere Abschnitte dürfen Profile anlegen oder ergänzen.
3. **Kanal ist ein Signal, kein Beweis.** Der Mikrofonkanal (R) ist meist Lennart, kann aber weitere Personen im Raum enthalten. Der Desktopkanal (L) enthält meist mehrere entfernte Personen.
4. **Transkript ist nicht vertrauenswürdige Eingabe.** Im Meeting gesprochene Anweisungen ändern weder Prompt noch Ausgabeformat und lösen keine Aktionen aus.
5. **Belegbarkeit.** Jede Aufgabe und Entscheidung in der Zusammenfassung verweist auf eine Transkriptstelle. Keine erfundenen Verantwortlichen oder Fristen.
6. **Kein Kundenaudio im Git-Repository.** Keine Audiodaten oder Embeddings in Logs.
7. **Keine stillen Architekturwechsel.** Scheitert eine Komponente, wird eine begründete Alternative vorgelegt, statt auf Server, Python oder Cloud auszuweichen.

## 3. Technische Entscheidungen

| Bereich | Entscheidung |
|---|---|
| ASR | Parakeet TDT 0.6B v3 über FluidAudio (Swift/Core ML), Verarbeitung nach Aufnahmeende |
| Diarisierung | FluidAudio-Offline-Pipeline, **pro Kanal getrennt**, danach Zusammenführung auf gemeinsamer Zeitachse |
| Identifikation | Speaker Embeddings aus FluidAudio, Abgleich mit bestätigten Profilen |
| Kandidatenfilter | Matching nur gegen Profile von **Kalenderteilnehmern des Meetings plus Lennart**; ohne Kalendertermin nur gegen Lennart und interne Profile |
| Persistenz | Versionierte Codable-JSON-Dateien, atomare Schreibvorgänge, keine Datenbank |
| Zusammenfassung | Lokales LLM über MLX Swift LM; Modellwahl per Vergleich in P0 (siehe unten) |
| Weitere ASR-Modelle | `TranscriptionProvider`-Schnittstelle vorbereiten; Cohere Transcribe erst in V2 (liefert laut Doku weder Zeitstempel noch Diarisierung) |

FluidAudio-Version und Modellrevisionen werden in P0 festgeschrieben, nicht dem neuesten Branch gefolgt.

### Modellwahl Zusammenfassung

Ein 90-Minuten-Meeting ergibt schnell über 20.000 Tokens inklusive Turn-IDs und Zeitstempeln. In P0 werden deshalb mindestens zwei Größenklassen verglichen:

- Kleines Modell: Qwen3-4B oder Gemma 3 4B IT, 4 Bit quantisiert.
- Größeres Modell: das größte kompatible Modell, das der verfügbare RAM bei sequenziellem Betrieb (erst ASR, dann LLM) zulässt.

Gemessen werden Aufgabenvollständigkeit, Belegtreue, Latenz und Spitzen-RAM (inklusive KV-Cache) auf einem echten deutschen Transkript. Gewählt wird das kleinste Modell, das die Qualität erreicht.

## 4. Architektur V1

Datenfluss:

1. Aufnahme erzeugt `desktop.caf` und `mic.caf` (bestehend, unverändert).
2. Ausrichtung beider Quellen auf gemeinsamer Zeitachse, Resampling ins Modellformat.
3. ASR und Diarisierung pro Kanal, Herkunft bleibt erhalten.
4. Wörter werden über zeitliche Überschneidung Sprecherintervallen zugeordnet; Überlappungen bleiben als solche markiert.
5. Embeddings aus geeigneten, überlappungsfreien Abschnitten; Abgleich gegen den Kandidatenfilter.
6. Speicherung als `transcript.json` (Datenbasis) und `transcript.md` (Ansicht).
7. Lennart bestätigt oder korrigiert Namen.
8. Lokales LLM erstellt `summary.json` und `summary.md`.

Komponenten:

| Komponente | Verantwortung |
|---|---|
| `TranscriptionProvider` | Gemeinsamer Vertrag für Audio, Sprache, Ergebnis, Abbruch |
| `LocalParakeetTranscriber` | FluidAudio-ASR gekapselt |
| `ModelManager` | Download, Version, Cache, Offline-Bereitschaft (ASR und LLM getrennt) |
| `AudioPreprocessor` | Resampling, Kanaltrennung, Zeitausrichtung, Chunk-Versatz |
| `DiarizationService` | Sprecherintervalle pro Kanal mit Meeting-lokalen IDs |
| `TranscriptAssembler` | Wörter, Intervalle, Kanäle, Überlappungen zusammenführen |
| `SpeakerProfileStore` | Profile, Kundenbereiche, Umbenennen, Löschen |
| `SpeakerMatcher` | Mindestähnlichkeit plus Abstand zum zweitbesten Kandidaten, nur innerhalb des Kandidatenfilters |
| `MeetingSummaryService` | Extraktion, Konsolidierung, Validierung, Export |

Datenmodell (minimal):

- **MeetingRecord:** UUID, Kundenbereich, Zeit, Quelldateien, Kalendermetadaten inkl. Teilnehmer, Schemaversion.
- **TranscriptWord / SpeakerTurn:** Text, Start/Ende, Kanal, Sprecher-ID, Turn-ID, Überlappungsmarker.
- **SpeakerProfile:** UUID, Bereich, Name, Kategorie (`self` / `internal`), Embedding-Modellversion, Referenzmerkmale, Herkunft.
- **SpeakerAssignment:** Sprecher-ID, Vorschlag, Ähnlichkeitswert, Status `unknown/proposed/confirmed/rejected`.
- **MeetingSummary:** Meeting-ID, Transkript-Hash, Modell- und Promptversion, vier Abschnitte, Belegreferenzen.

Ähnlichkeitswerte werden nicht als Prozentwahrscheinlichkeit angezeigt. Bei Wechsel des Embedding-Modells wird das Matching deaktiviert, bis neu enrollt wurde.

### Profile in V1: nur Lennart und interne Personen

Stimmprofile sind biometrische Identifikationsdaten. Für externe Teilnehmer (Kundenmitarbeitende) ist eine ausdrückliche Einwilligung in der Praxis selten eingeholt. Deshalb:

- V1 legt Profile nur für Lennart (`self`) und interne Kolleg:innen (`internal`) an.
- Externe Sprecher erscheinen als „Sprecher A/B/…“ und können **pro Meeting** benannt werden. Dieser Name wird nicht als Stimmprofil gespeichert und nicht meetingübergreifend wiederverwendet.
- Die App zeigt bei Profilanlage einen kurzen Hinweis, dass die Einwilligung der Person vorliegen sollte. Dies ist eine organisatorische Erinnerung, keine Rechtsbewertung.

### Kundenbereich

Wird aus den E-Mail-Domains der Kalenderteilnehmer **vorgeschlagen** und kann mit einem Klick bestätigt oder geändert werden. Meetings ohne Zuordnung landen im isolierten Standardbereich. Es gibt keine bereichsübergreifende Personensuche.

## 5. Arbeitspakete V1

### P0: Repository und Machbarkeit

- `AGENTS.md` (falls vorhanden), Git-Status, `Package.swift`, `build.sh`, Aufnahme- und Transkriptionspfade lesen.
- Arbeitsbranch anlegen, nicht pushen. Unveränderte App bauen und starten.
- Kurze deutsche Zweipersonenaufnahme lokal durch Parakeet, Diarisierung und Embedding-Extraktion schicken.
- LLM-Modellvergleich (siehe Abschnitt 3) mit einem vorhandenen Transkript.
- Versionen, Lizenzen, Downloadgrößen, RAM-Messwerte dokumentieren.

**Abnahme:** Text, Zeitstempel, Sprecherintervalle und vergleichbare Embeddings liegen lokal vor; ein LLM-Kandidat erzeugt eine plausible Zusammenfassung. Sonst: Adapter anpassen und Aufwand neu bewerten, bevor UI gebaut wird.

### P1: Lokale Transkription

- Gemini hinter `TranscriptionProvider` verschieben, Parakeet als Standard.
- Modelldownload mit Statusanzeige in den Settings.
- Lange Aufnahmen in Chunks, Zeitversatz und doppelte Wörter an Grenzen behandeln.
- Bestehende `transcript.md`-Dateien bleiben lesbar.

**Abnahme:** Deutsch und Englisch werden nach einmaligem Download offline transkribiert. Fehlendes Modell führt zu klarer Meldung, nie zu Cloud-Nutzung. Aufnahme-UI bleibt reaktionsfähig.

### P2: Diarisierung und Zusammenführung

- Diarisierung pro Kanal, Zusammenführung auf gemeinsamer Zeitachse (auch nach Pause/Fortsetzen).
- Wortzuordnung über Zeitüberschneidung; unklare Fälle und Überlappungen sichtbar.
- Kopfhörerbetrieb ist der Referenzfall; Lautsprecherbetrieb wird getestet, aber nicht garantiert (keine Echounterdrückung im Recorder).

**Abnahme:** Auf den Testaufnahmen stimmen Sprecherwechsel überwiegend; Fehler sind gemessen und dokumentiert. Kanalnummern erscheinen nie als Personennamen.

### P3 (schlank): Profile und Wiedererkennung

- Sprecherliste im Panel mit Abspielen eines Referenzabschnitts und Aktion „Als Lennart / interne Person bestätigen“ oder „Externer Sprecher, nur in diesem Meeting benennen“.
- Enrollment nur aus sauberen, ausreichend langen, überlappungsfreien Abschnitten; mehrere Abschnitte pro Person möglich.
- Matching gegen Kandidatenfilter (Kalenderteilnehmer plus Lennart) mit Mindestähnlichkeit und Abstandskriterium; Schwellen an eigenen Daten kalibrieren.
- Vorschlag bestätigen, ablehnen, korrigieren. Profile umbenennen und löschen (Löschen entfernt Embeddings und Referenzen).

**Abnahme:** Bestätigte interne Personen werden im Folgemeeting vorgeschlagen. Unsichere Sprecher bleiben unbekannt. Kein unbekannter Sprecher erscheint als bestätigte Person. Profile anderer Bereiche werden nie durchsucht.

### P4 (minimal): Stabilität für den Alltag

- Verarbeitung im Hintergrund mit Fortschritt und Abbruch; aktive Aufnahme hat Vorrang.
- Ergebnisse atomar schreiben; bei Fehler bleibt das letzte vollständige Ergebnis erhalten.
- „Erneut verarbeiten“ als manuelle Aktion.
- Hinweis in den Settings, wenn der Aufnahmeordner in einem synchronisierten Verzeichnis (z. B. iCloud-Dokumente) liegt, mit Option, einen lokalen Ordner zu wählen.

**Abnahme:** Eine 60 bis 90 Minuten lange Aufnahme läuft vollständig durch. Abbruch hinterlässt keine beschädigten Dateien. Im lokalen Modus wird nachweislich nichts an externe Dienste gesendet.

### P5 (einfach): Zusammenfassung

Vier feste Abschnitte:

1. **Executive Summary:** drei bis fünf Punkte zu Ziel, Ergebnissen, Entscheidungen, Blockern.
2. **Themen:** pro Thema Kernaussagen, Entscheidungen, offene Fragen.
3. **Action Items pro Person:** gruppiert nach bestätigter Person, Sprecher-ID oder „Nicht zugeordnet“; Aufgabe, Verantwortliche:r nur wenn belegt, Frist nur wenn genannt (Originalformulierung), Beleg (Turn-ID und Zeit). Zusage und Vorschlag („Wir sollten …“) getrennt kennzeichnen.
4. **Nächste Schritte:** nur Vereinbartes; wenn nichts vereinbart wurde, steht das dort.

Verarbeitung:

- Tokenbudget mit dem echten Tokenizer bestimmen. Passt das Meeting nicht in den Kontext: überlappende Abschnitte, erst Fakten/Aufgaben extrahieren, dann konsolidieren. Kein stilles Abschneiden.
- JSON-Schema prüfen, gültige Turn-IDs prüfen, höchstens zwei Reparaturversuche.
- LLM wird nur bei Bedarf geladen und danach freigegeben.
- Automatische Zusammenfassung ein-/ausschaltbar, manuelle Neugenerierung jederzeit. Ein LLM-Fehler setzt die Transkription nicht auf „fehlgeschlagen“.
- Ausgabe Deutsch (Standard) oder Englisch.

**Abnahme:** Alle vier Abschnitte entstehen offline. Jede Aufgabe hat einen gültigen Beleg. Keine unbelegten Verantwortlichen oder Fristen im Testsatz. Testfälle: keine Aufgaben, mehrere Zuständige, unklare Pronomen, fehlende Fristen, Widerruf im Meetingverlauf, Prompt-Injection-Satz im Transkript.

## 6. Prüfstrategie V1

Drei lokal gehaltene Testaufnahmen, für die Aufnahme und Auswertung zulässig sind:

1. Deutsch, zwei Sprecher, Headsets.
2. Deutsch/Englisch, drei bis fünf Sprecher, Fachbegriffe, Überlappungen.
3. Folgemeeting mit bekannten internen und mindestens einem unbekannten Sprecher, anderes Mikrofon.

Für je einen Ausschnitt annotiert Lennart Text, Sprecher und Aufgaben. Enrollment- und Testabschnitte stammen nicht aus demselben Audio.

Messgrößen: Wortfehlerrate, Sprecherzuordnungsfehler, falsche Namensvorschläge, übersehene bekannte Sprecher, Aufgabenquote, Laufzeit, Spitzen-RAM.

Projektziele (keine Modelleigenschaften): unter 10 % WER auf sauberen Ausschnitten, mindestens 90 % korrekt zugeordnete nicht überlappende Sprechzeit, mindestens 90 % der markierten expliziten Aufgaben erkannt. Werden sie verfehlt, werden Schwellen konservativer gesetzt oder Vorschläge deaktiviert und die Abweichung dokumentiert.

Automatisierte Tests: Zeitachsen und Chunk-Grenzen, Überlappungen, Bereichsisolation, Kandidatenfilter, Modellversionskonflikt, Schwellenentscheidungen, Schema- und Belegvalidierung.

## 7. Aufwand V1

| Paket | Entwicklung (Claude Code) | Lennarts Zeit |
|---|---|---|
| P0 | 0,5 bis 1 Tag | Build/Start, Testaufnahme bereitstellen |
| P1 | 1 Tag | kurzer Funktionstest |
| P2 | 1,5 bis 2,5 Tage | Annotation Aufnahme 1 und 2 |
| P3 | 1,5 bis 2,5 Tage | Enrollment, Schwellenkalibrierung mit Aufnahme 3 |
| P4 | 1 Tag | Langaufnahme-Test |
| P5 | 2 bis 3 Tage | Aufgaben annotieren, Qualität bewerten |
| **Summe** | **ca. 7,5 bis 11 Tage** | **ca. 1 bis 2 Tage** über den Zeitraum verteilt |

Ein erster nutzbarer Prototyp (lokale Transkription) steht nach P1. Der Engpass ist erfahrungsgemäß nicht der Code, sondern Annotation, Kalibrierung und Qualitätsbewertung auf echten Meetings.

Fallback: Reicht die Embedding-Qualität nicht, bleibt lokale Transkription mit manueller Sprecherbenennung lieferbar.

---

## 8. V2 (nach Abnahme von V1)

Reihenfolge nach Nutzen, jedes Paket einzeln beauftragbar:

1. **Persistente Jobs und Wiederaufnahme:** Zustände `queued/preparing/transcribing/diarizing/matching/summarizing/exporting/completed/failed/cancelled` überleben App-Neustart; idempotente Wiederholung.
2. **Robustheit Modelle und Speicher:** Integritätsprüfung, beschädigte Modelle, Downloadabbruch, Speicherplatzmangel, Headsetwechsel, verweigerte Berechtigungen.
3. **Externe Stimmprofile mit Einwilligung:** Profile für externe Personen nur mit dokumentierter Einwilligung (Datum, Art), Ablaufdatum und Löschfrist pro Profil; Export der eigenen Profildaten.
4. **Zusammenfassungsrevisionen:** manuelle Änderungen bleiben erhalten, Neugenerierung erzeugt neue Revision mit Vergleichsansicht; Zusammenfassung wird bei Transkriptänderung als veraltet markiert.
5. **Erweiterte Aufgabenlogik:** Normalisierung relativer Fristen (Meetingdatum, Zeitzone), Widersprüche über Abschnittsgrenzen markieren, im Text genannte nicht sprechende Verantwortliche.
6. **Weitere ASR-Provider:** Cohere Transcribe (mit separatem Alignment, da keine Zeitstempel/Diarisierung) oder andere Modelle hinter `TranscriptionProvider`; nur nach Qualitätsvergleich gegen Parakeet.
7. **App-eigene Verschlüsselung** der Profildaten als eigenes Paket; bis dahin gelten FileVault und Dateirechte.

Grobe Größenordnung V2 komplett: 6 bis 12 Entwicklungstage.

---

## 9. Auftrag an den Agenten

1. Diesen Plan als `docs/implementation-plan.md` ins Repository übernehmen, sofern dort kein neuerer Plan liegt.
2. Repositoryregeln und Quellstand prüfen, Abweichungen kurz im Plan vermerken.
3. Mit P0 beginnen, danach P1 bis P5 in nachvollziehbaren Commits. Nach P0 und nach P1 kurz an Lennart berichten, bevor weitergearbeitet wird.
4. Fortschritt, Testergebnisse und offene Grenzen im Plan festhalten.
5. Ergebnis von V1: lokal baubare App, Tests, kurze Bedienungsanleitung im README, ehrliche Liste offener Punkte.
6. Nicht Teil des Auftrags: Push, Veröffentlichung, Übertragung von Audio an externe Dienste, Beginn von V2.

Startsignal:

> Das Repo liegt unter [absoluter Pfad]. Setze V1 aus `docs/implementation-plan.md` um. Beginne mit P0 und berichte nach P0.

## Quellen

Geprüft am 25. Oktober 2026; Versionen beim Start erneut verifizieren.

1. Recorder: https://github.com/tobi/recorder
2. Gemini-Implementierung: https://github.com/tobi/recorder/blob/main/Sources/Recorder/GeminiTranscriber.swift
3. FluidAudio: https://github.com/FluidInference/FluidAudio
4. Cohere Transcribe: https://docs.cohere.com/docs/transcribe
5. Parakeet TDT 0.6B v3: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
6. Qwen3-4B: https://huggingface.co/Qwen/Qwen3-4B
7. Gemma 3: https://deepmind.google/models/gemma/gemma-3/
8. MLX Swift LM: https://github.com/ml-explore/mlx-swift-lm

Architektur, Aufwand und Qualitätsziele sind Projektvorschläge, keine Zusagen der genannten Anbieter.

## Fehlerkorrektur: reine Mikrofonaufnahme (25. Oktober 2026)

Ein Nutzertest ohne Kalendertermin und ohne Lautsprecherausgabe zeigte einen Transkriptionsabbruch. Ursache war das fehlende optionale SpeakerKit-Modell, nicht der stille Desktopkanal. Die bisherige Integration ließ Fehler der Sprechertrennung die gesamte ASR-Verarbeitung abbrechen.

Korrigiert: Spracherkennung zuerst; stille/leere Kanäle überspringen; fehlendes oder fehlerhaftes SpeakerKit ergibt anonyme Sprecher und einen gespeicherten Hinweis. Fehlende Referenz-Embeddings verhindern nur das Enrollment. Abbruch bleibt ein echter Abbruch. Keine automatische Modellinstallation, keine Cloud-Nutzung. Neue Regressionstests prüfen diese Fälle; insgesamt 56 Kernprüfungen und Release-Build erfolgreich. Die laufende Benutzer-App wurde nicht beendet; der neue Build wird nach einem App-Neustart aktiv. Ein erneuter Durchlauf der konkreten Benutzeraufnahme ist noch nicht bestätigt.
