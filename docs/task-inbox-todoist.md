# Aufgaben-Inbox und Todoist

Stand: 25. Oktober 2026. Neuer Branch: `codex/meeting-task-inbox`. Vom Nutzer ausdrücklich beauftragte Erweiterung des bisherigen Umfangs.

**Aktueller Bedienablauf:** Die nachfolgende ursprüngliche Beschreibung wurde um eine Meeting-Auswahl und gemeinsame Projekt-/Tag-Vorgaben erweitert. Exportiert werden jetzt ausschließlich eigene Aufgaben. Globale Namensvergleiche und Fremdzuweisungen werden dafür nicht mehr verwendet. Maßgeblich ist [Todoist je Meeting](meeting-todoist-sync.md).

## Reihenfolge der Umsetzung

1. Dauerhafte Verarbeitungswarteschlange.
2. Aufgaben-Inbox über mehrere Meetings.
3. Zuständigkeit („Meine Aufgabe“, „Warten auf“, ungeklärt) und Fristenprüfung.
4. Zielprojekt, Abschnitt, Labels, Priorität und ausdrückliche Todoist-Zuweisung.
5. Dauerhafter Exportstatus und Duplikatschutz.
6. CSV-Export, anschließend direkte Übertragung ausgewählter Aufgaben.

## Mehrere Meetings hintereinander

Aufnahmen haben Vorrang vor Nachverarbeitung. Ein neuer Aufnahmestart unterbricht die laufende Nachverarbeitung und stellt den Auftrag wieder auf wartend. Sobald keine Aufnahme, Audiomischung oder Bereinigung läuft, arbeitet ein einzelner Worker die Warteschlange ab. Ein bereits gespeichertes Offline-Transkript ist ein Zwischenstand: Bei einer Unterbrechung der Zusammenfassung muss es nicht erneut transkribiert werden. Die Reihenfolge richtet sich nach dem Einreihen nach dem Speichern/Mischen.

Die Warteschlange liegt mit privaten Dateirechten unter `Application Support/Recorder/processing-queue.json`. Beim Neustart werden unterbrochene laufende Aufträge erneut vorgemerkt. Fehlerhafte Aufträge sind unter **Settings → Local → Verarbeitung** sichtbar und lassen sich wiederholen oder verwerfen; Verwerfen löscht keine Aufnahme. Ausstehende oder fehlerhafte Aufträge sperren die zeitgesteuerte Bereinigung, bis sie bearbeitet oder verworfen sind. Explizites Abbrechen wird als Fehler mit Wiederholungsmöglichkeit gespeichert.

Audio wird weiterhin erst nach erfolgreicher Transkription und Zusammenfassung gemäß der gewählten Option gelöscht. Bevor eine Zusammenfassung diese Löschung auslöst, müssen ihre Aufgaben erfolgreich in der Inbox gespeichert sein. Die Warteschlange ersetzt keine Absturzsicherung der laufenden Aufnahme oder des Audiomischens: Vor dem Einreihen können bei einem Prozessabsturz Rohdateien zur manuellen Wiederherstellung übrig bleiben. Im Modus „Transcript only“ gibt es keine Audio-Wiederherstellung.

## Aufgaben später prüfen

**Aufgaben-Inbox öffnen…** im Menüleistenfenster öffnet ein eigenes, vergrößerbares Fenster. Nach jeder lokalen Zusammenfassung werden strukturierte Aufgaben eingelesen. Bestehende Zusammenfassungen werden beim Start sowie mit **Zusammenfassungen einlesen** übernommen.

- Aufgaben sind zunächst ungeprüfte Entwürfe. Originalzuständigkeit, genannte Frist, Meetingname, Zeitpunkt und kurze Textbelege bleiben sichtbar.
- Ein ausdrücklich hinterlegter eigener Name schlägt neue Aufgaben dieser bestätigten Person als eigene vor. Eine Sprecherzuordnung bleibt vom Todoist-Konto getrennt.
- Andere Personen können als „Warten auf“ geführt werden. Das erzeugt beim Export einen entsprechend benannten Nachverfolgungspunkt. Zuweisung an Mitglieder geteilter Todoist-Projekte erfolgt nur nach ausdrücklicher Auswahl.
- „Morgen“, „heute“, eindeutige Wochentage, ISO-Daten und vollständige deutsche Datumsangaben werden deterministisch aus dem Meetingdatum und der lokalen Zeitzone vorgeschlagen. Mehrdeutige Ausdrücke bleiben zur manuellen Prüfung offen. Ausführungstag und Deadline sind getrennte optionale ISO-Datumsfelder; Uhrzeiten und Wiederholungen werden noch nicht unterstützt.
- Ein Vorschlag wird erst durch ausdrückliche Prüfung zur Aufgabe. Abgesagte Aufgaben sind nicht exportierbar. Unbekannte Zuständigkeiten müssen zuerst geklärt werden.
- **Speichern und als geprüft auswählen** gibt den Entwurf für den Export frei. Jede spätere Änderung verlangt erneute Prüfung. Die Auswahl kann in der Liste geändert werden.
- Sprecher-/Transkriptänderungen machen bestehende Entwürfe erneut prüfpflichtig. Nach einer neuen Zusammenfassung werden Quellen aktualisiert; eigene Aufgabentitel und Notizen bleiben erhalten. Entfallene Aufgaben werden als veraltet markiert. Vor neuen Exporten werden noch vorhandene Quellen zusätzlich geprüft.

Inbox, Kundenbereich-Zuordnungen, Exportbelege und eingefrorene Versandaufträge liegen getrennt von Audio unter `Application Support/Recorder/TaskInbox/inbox.json` mit privaten Rechten. Sie überleben App-Neustarts und die Aufnahmebereinigung. Sie enthalten Text und müssen bei einer gewünschten vollständigen Datenlöschung gesondert entfernt werden.

## Zielprojekt und CSV

Im Aufgabenentwurf lassen sich Projekt, Abschnitt, Labels und Priorität wählen. **Ziel für neue Aufgaben dieses Kundenbereichs merken** speichert die Zuordnung für künftige Entwürfe; bereits bearbeitete Aufgaben werden nicht heimlich geändert. Ohne Projekt geht eine direkte Übertragung an den Todoist-Eingang. Projekte/Abschnitte werden erst mit dem entsprechenden Button geladen.

**CSV exportieren…** exportiert nur geprüfte, ausgewählte Aufgaben aus genau einem Zielprojekt. Die Datei im passenden Todoist-Projekt über dessen CSV-Import einlesen. Abschnittszeilen, Labels, Priorität, Beschreibung, Termine und ausgewählte Zuweisungen sind enthalten. Kommas, Anführungszeichen, Unicode und Zeilenumbrüche werden maskiert; Formeln werden beim Öffnen in Tabellenprogrammen entschärft.

Ein CSV-Export wird vor dem Schreiben dauerhaft eingefroren und sperrt die betroffenen Aufgaben für weiteren Versand. Bei Schreibfehlern kann derselbe vorbereitete Export erneut gespeichert werden. **Jede CSV nur einmal in Todoist importieren**: Der Recorder kann externe manuelle Mehrfachimporte nicht erkennen. „CSV vorbereitet“ bestätigt keine tatsächliche Übernahme durch Todoist.

## Direkte Todoist-Übertragung

Unter **Settings → Todoist** den persönlichen API-Token speichern. Er liegt ausschließlich im macOS-Schlüsselbund und wird weder in UserDefaults noch in der Inbox, Exportdateien oder Logs gespeichert. Der persönliche Token gewährt Kontozugriff; CSV funktioniert ohne Verbindung. Eine OAuth-Anmeldung ist nicht enthalten.

Nach Prüfung die gewünschten Aufgaben auswählen und **An Todoist senden…** anklicken. Die Bestätigung nennt Aufgaben und Zielprojekte. Übertragen werden die ausgewählten Titel, Zuständigkeiten/Zuweisungen, Termine, Labels, Notizen, Meetingnamen und kurzen Belege. Kein Audio, keine Stimmmerkmale und kein vollständiges Transkript. Der Netzwerkzugriff beschränkt sich auf Todoist-Projektabfragen und ausdrücklichen Aufgabenversand; lokale Transkription und Zusammenfassung bleiben lokal.

Der Client verwendet die aktuelle Todoist API v1 und deren Sync-`item_add` mit stabiler UUID. Vor dem ersten Netzwerkversuch werden UUID und vollständiger Auftrag atomar gespeichert. Nach unklaren Antworten bleibt der Auftrag gesperrt und kann mit identischen Daten und derselben UUID wiederholt werden. Erst eine eindeutige Bestätigung mit Aufgaben-ID zählt als Erfolg. Eindeutige Ablehnungen (etwa fehlende Berechtigung oder ein ungültiges Projekt) geben den Entwurf zur Korrektur frei und verlangen eine neue Prüfung; unklare Netzwerk-/Serverfehler behalten den unveränderten Versandauftrag. Ein API-Fehler wird ohne rohe Antwortdaten oder Token angezeigt. Erfolgreiche Aufgaben werden nicht automatisch geändert oder erneut erzeugt; spätere Änderungen in Todoist werden noch nicht zurücksynchronisiert. HTTP-Weiterleitungen sind deaktiviert.

Wiederholte Zusammenfassungen werden nach Meeting, belegten Textstellen und Aufgabentext abgeglichen. Einzelne umformulierte Aufgaben derselben Textstelle behalten ihre Identität. Mehrdeutige zusätzliche Aufgaben aus bereits verwendeten Textstellen brauchen eine gesonderte Duplikatprüfung. Das ist keine allgemeine semantische Erkennung gleichbedeutender Aufgaben aus verschiedenen Meetings.

## Technische Quellen und Abnahme

- [Todoist API v1: Projekte, Mitglieder, Abschnitte, Sync-Befehle und Datumsfelder](https://developer.todoist.com/api/v1/)
- [Offizielles CSV-Format und Import](https://www.todoist.com/help/articles/208821185-Project-templates)

Automatisierte Prüfungen verwenden ausschließlich temporäre Dateien, synthetische Meetings und simulierte HTTP-Antworten. Es werden weder echte Aufgaben angelegt noch echte Tokens für Tests benötigt. Reale Kontoübernahme, Gerätewechsel, lange Meetings und mehrere unmittelbar folgende echte Aufnahmen bleiben praktische Abnahmeszenarien.

Prüfstand: **179 XCTest-Tests, 12 bewusst ausgelassen, 0 Fehler**, inklusive lokaler LLM-Inferenz mit synthetischen Daten; **56 unabhängige Kernprüfungen bestanden**. Die Inbox-Oberfläche wurde mit künstlichen Daten gerendert und visuell geprüft.
