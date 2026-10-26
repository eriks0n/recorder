# Fachbegriffe, Zusammenfassungs-Template und Mikrofon

Stand: 26. Oktober 2026, Entwicklungsbranch `codex/meeting-task-inbox`.

## Fachbegriffe und Namen

Unter **Settings → Transcription → Namen, Marken und Fachbegriffe** einen Begriff pro Zeile eintragen, etwa:

```text
Secjur
Amin
Armin
DSGVO
```

Die Liste wird lokal in den macOS-App-Einstellungen gespeichert und als Whisper-Kontext bei der Erkennung verwendet. Keine Cloud-Anfrage. Wichtige Begriffe zuerst: maximal 2.000 Zeichen, im Modell bis zu 200 Tokens. Ganze Begriffe werden in Listenreihenfolge aufgenommen; passt ein Begriff nicht mehr hinein, endet die Auswahl. Doppelte Schreibweisen werden ohne Beachtung der Groß-/Kleinschreibung zusammengeführt. Leer bedeutet keine Erkennungshilfe.

Die Liste kann die Schreibweise verbessern, garantiert aber keine fehlerfreien Texte. Sie enthält gewünschte Schreibweisen, keine Ersetzungsregeln: `secure → Secjur` wird nicht als Regel interpretiert. Amin und Armin können beide vorkommen; Recorder ersetzt deshalb keine ähnlich klingenden Namen pauschal. Bei Unsicherheit anhand des Audios prüfen. Bereits gespeicherte Texte ändern sich nicht; erneute Offline-Transkription benötigt noch vorhandenes Audio.

Die Live-Transkription übernimmt die Liste beim Aufnahmestart. Offline-Aufträge sichern die Liste beim Einreihen in die Warteschlange und behalten sie auch nach Neustart oder Wiederholen. Alte Aufträge ohne dieses Feld verwenden die aktuellen Einstellungen.

WhisperKit 1.1.0 hat mit `promptTokens` einen [bekannten Fehler bei Wortzeitstempeln](https://github.com/argmaxinc/argmax-oss-swift/issues/542). `VocabularySegmentSeeker` korrigiert den Zeilenversatz der Alignment-Matrix, ohne den Abhängigkeits-Checkout zu verändern. Die Korrektur ist an diese festgelegte WhisperKit-Version gebunden und muss bei einem Update geprüft werden. Matrix-Regressionsprüfung und ein echter Modelldurchlauf mit synthetischer Sprache bestehen. Ein Qualitätsvergleich echter deutscher Namen steht noch aus.

## Eigenes Markdown-Template

Unter **Settings → Local → Markdown-Template** bearbeiten und **Template speichern** wählen. **Standard einsetzen** füllt ein Beispiel zum Bearbeiten ein; danach speichern. Leer speichern stellt das bisherige Layout wieder her.

```markdown
# {{meeting_title}}

## Das Wichtigste
{{executive_summary}}

## Besprochene Themen
{{topics}}

## Vereinbarte Aufgaben
{{action_items}}

## Nächster Schritt
{{next_steps}}
```

`{{executive_summary}}` ist erforderlich; die anderen Platzhalter sind optional und dürfen umsortiert oder mehrfach verwendet werden. Unbekannte Platzhalter und Templates über 20.000 Zeichen werden mit einer Meldung abgelehnt. Der Meetingtitel fällt ohne eigenen Titel auf „Meeting“ zurück. Die Sprache der erzeugten Inhalte folgt weiterhin der Zusammenfassungs-Sprache; eigene Überschriften bleiben unverändert.

Das Template formatiert die bereits extrahierten, belegten Daten. Es steuert keine Modellaktionen und führt weder Code noch Befehle aus. Platzhalter werden nur einmal ersetzt; Platzhaltertext in einem Meetingtitel wird nicht erneut interpretiert. Aufgaben, Belege und Todoist-Inbox bleiben unabhängig von ausgelassenen Markdown-Abschnitten vollständig in den strukturierten Daten erhalten. Bestehende Zusammenfassungen behalten ihr gespeichertes Template. Für ein neues Layout die Zusammenfassung erneut beauftragen. Neue Aufträge sichern das Template in der Warteschlange; alte Aufträge verwenden die aktuellen Einstellungen.

## Mikrofon

Unter **Settings → Recording → Mikrofon → Eingabequelle** zwischen **Systemstandard** und einer festen Quelle wählen. **Quellen aktualisieren** liest die aktuell angeschlossenen Eingabegeräte erneut ein. Die Auswahl gilt für die nächste Aufnahme und ist während einer Aufnahme gesperrt. Recorder ändert nicht die macOS-weite Standardquelle. Die Geräte-ID wird dauerhaft gespeichert, damit eine wechselnde Reihenfolge der Geräte nicht zur falschen Auswahl führt.

„Beste Quelle“ lässt sich nicht zuverlässig automatisch bestimmen: Ein gutes USB-Mikrofon kann besser sein als ein Headset; Bluetooth kann bei aktiviertem Mikrofon seine Audioqualität ändern. Mit einer festen Quelle ist die Auswahl vorhersehbar. Ein fehlendes Gerät verhindert den Aufnahmestart mit einer klaren Meldung. Bei gemeldetem Gerätewechsel wird die feste Quelle geprüft; ihr Verlust beendet die Aufnahme über die vorhandene Fehlerbehandlung. Systemstandard folgt weiterhin den Audio-Routen von macOS. Reale Wechsel-/Abziehversuche sind Teil der Geräteabnahme, nicht durch simulierte Tests abgedeckt.

## Aufnahmedauer und Speicher

Es gibt kein eingebautes 30-, 60- oder 120-Minuten-Limit. Aufnahme und anschließendes Zusammenmischen schreiben in Blöcken; sie sammeln nicht die gesamte Aufnahme im RAM. Die Offline-Verarbeitung ist dagegen noch nicht vollständig auf konstanten Speicher begrenzt:

- Ein Kanal wird vollständig als 16-kHz-Float-Audio geladen: etwa 230 MB je Stunde, etwa 920 MB bei vier Stunden, zuzüglich temporärer Konvertierungspuffer, Chunk-Kopien, Whisper-/Sprechermodelle und deren Arbeitsdaten.
- Die beiden Kanäle laufen nacheinander. Die Whisper-Offline-Verarbeitung verwendet einen Worker, um gleichzeitige Modellarbeit zu begrenzen.
- Die Zusammenfassung teilt Text anhand des echten Tokenizers in Abschnitte und konsolidiert deren Ergebnisse. Es gibt keine stille Kürzung auf die ersten Minuten. Wenn ein einzelner Abschnitt oder die Konsolidierung das Kontextbudget übersteigt, meldet die App einen Fehler und erhält das Transkript.
- Bei zwei rohen Mono-Float-Spuren mit jeweils 48 kHz fallen zusammen ungefähr 1,38 GB pro Stunde an; der AAC-Mix zusätzlich ungefähr 58 MB pro Stunde. Vier Stunden benötigen damit vor Bereinigung ungefähr 5,8 GB. Abweichende Eingaberaten verändern den Rohdatenbedarf. Automatisches Audiolöschen greift erst nach erfolgreicher Textverarbeitung und reduziert daher nicht den Speicherbedarf während der Aufnahme.
- **Pause** schreibt weiterhin Stille, damit beide Zeitachsen zusammenpassen; sie verkürzt weder Datei noch spätere Zeitachse. Für lange Pausen besser speichern und eine neue Aufnahme beginnen.
- Automatisches Stoppen bei Stille ist standardmäßig eingeschaltet (fünf Minuten auf beiden Kanälen). Unter **General → Auto-stop** anpassen oder abschalten, wenn ein Meeting lange stille Phasen enthält.

30–60 Minuten sind der vorgesehene Einsatzbereich, aber noch nicht mit einem echten Langlauf abgenommen. Zwei bis vier Stunden sind durch kein App-Zeitlimit ausgeschlossen; je nach Mac steigen Speicherbedarf, Verarbeitungszeit und Fehlerwahrscheinlichkeit. An natürlichen Pausen in neue Aufnahmen aufzuteilen ist aktuell sinnvoll. Für verlässlich durchgehende Vierstundenaufnahmen fehlen noch ein gemessener Langlauftest und eine vollständig abschnittsweise Offline-/Sprecherverarbeitung mit stabiler Sprecherzuordnung über Abschnittsgrenzen. Die Wiederanlauf-Warteschlange bewahrt den Auftrag, startet den unterbrochenen Transkriptionsschritt jedoch erneut.

Die verwendete WhisperKit-Laderoutine konvertiert außerdem Dateiframezahlen zu `UInt32`. Bei den 48-kHz-Mixdateien liegt deren rechnerische Grenze bei ungefähr 24,9 Stunden – ausdrücklich keine zugesicherte Aufnahmedauer. Speicher und Verarbeitung können schon deutlich früher begrenzen. Ein 2–4-Stunden-Meeting erreicht diese Zahlengrenze nicht.

## Nachweise

- Gesamte XCTest-Suite: 210 Fälle, zwölf bewusst ausgelassene Geräte-/Aufnahmefälle, keine Fehler; beide lokalen Modelle mit synthetischen Testdaten ausgeführt.
- Enthalten sind Fachbegriffsnormalisierung, Templatevalidierung, unveränderte strukturierte Aufgaben, alte JSON-Daten, persistierte Auftragsoptionen, Zeitstempel-Matrix und echter Whisper-Durchlauf, Einstellungsdarstellung und Textmenü.
- 56 unabhängige Kernprüfungen bestanden. Reale Mikrofonwahl, Sprachqualität und Langaufnahmen sind weiterhin manuell abzunehmen.
