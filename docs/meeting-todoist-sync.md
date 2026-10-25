# Todoist je Meeting: eigene Aufgaben auswählen und übertragen

Aktualisierung vom 25. Oktober 2026. Umsetzung auf `codex/meeting-task-inbox`.

## Bedienung

1. **Settings → Todoist** öffnen, den persönlichen API-Key im sichtbaren umrandeten Passwortfeld eintragen (tippen, ⌘V oder **Einfügen**) und **Verbindung prüfen und sicher speichern** klicken. Der Key wird vor dem Speichern gegen das Todoist-Konto geprüft. Nur bei Erfolg wird er im macOS-Schlüsselbund gespeichert; ein falscher neuer Key überschreibt keinen vorhandenen funktionierenden Zugang. Die Eingabe wird anschließend geleert. Ein bereits gespeicherter Key wird niemals im Klartext angezeigt.
2. **Aufgaben-Inbox öffnen…**, anschließend das gewünschte **Meeting** wählen. „Alle Meetings ansehen“ dient der Übersicht; daraus wird kein gemischter Stapel synchronisiert.
3. **Projekte und Tags laden** ruft die eigenen Todoist-Projekte, Abschnitte und Tags ab. **# Projekt für dieses Meeting** wählen; **@ Tags** aus der Liste ergänzen oder mit Kommas eingeben. Ein führendes `@` wird entfernt, doppelte Tags werden zusammengeführt. Kein Projekt bedeutet Todoist-Eingang; keine Tags ist ebenfalls zulässig.
4. Unter **Ich bin im Meeting…** den eigenen Sprecher auswählen. Bei mehreren Sprecher-IDs derselben Person können mehrere markiert werden. **Für Meeting übernehmen** speichert Projekt, Tags und Sprecherzuordnung dauerhaft. Die Vorgaben gelten für alle noch nicht exportierten Aufgaben dieses Meetings und später neu erkannte Aufgaben. Andere Meetings, bereits gesendete Aufgaben und gesetzte Termine bleiben unverändert.
5. Aufgaben einzeln prüfen: „Meine Aufgabe“ ist exportierbar; „Warten auf andere Person“ und „Noch ungeklärt“ bleiben lokale Einträge. Eine unklare Aufgabe kann ausdrücklich manuell sich selbst zugewiesen werden. Gleiche Namen mehrerer Sprecher werden nicht automatisch einer Person zugeordnet. Ein globaler gleicher Anzeigename genügt nicht als Identitätsnachweis.
6. Pro Aufgabe optional das **Todoist-Fälligkeitsdatum** und eine **verbindliche Deadline** über Datumsauswahl setzen. Ohne eingeschaltetes Datumsfeld wird kein Datum übertragen. Fristen aus dem Meeting bleiben als Quelle sichtbar; relative Vorschläge beziehen sich auf das Meetingdatum, nicht auf den Tag des Exports.
7. **Prüfen und für Todoist auswählen** speichert und bestätigt die eigene Aufgabe. Über die Checkbox in der Liste kann sie wieder abgewählt werden. Danach **Mit Todoist synchronisieren…** klicken. Die Bestätigung nennt die ausgewählten Aufgaben, Projekte, Tags und Fälligkeitsdaten.

Nur die ausdrücklich ausgewählten, geprüften eigenen Aufgaben dieses Meetings werden neu angelegt. Dies ist ein gerichteter Export: Bereits übertragene Aufgaben werden weder erneut angelegt noch nachträglich aus dem Recorder überschrieben; Änderungen in Todoist werden nicht zurückgelesen. Für geteilte Projekte werden eigene Aufgaben dem verbundenen Todoist-Konto zugewiesen. Frühere Fremdzuweisungen werden nicht übernommen. CSV bleibt optional verfügbar und enthält ebenfalls nur eigene Aufgaben.

## Änderungen und Fehlerfälle

- Eine Änderung an Projekt, Tags, Zuständigkeit, Terminen oder Aufgabeninhalt hebt Prüfung und Auswahl auf. Eine neue Sprecher-/Transkriptquelle verlangt erneut Prüfung. Wenn die zuständige Person geändert wurde, bleibt eine frühere „Meine Aufgabe“-Zuordnung nicht ungeprüft bestehen.
- Gleichzeitige Bearbeitung und Meeting-Vorgaben können einander nicht unbemerkt überschreiben: Entwürfe besitzen eine Revisionskennung. Ein veralteter Editor wird neu geladen bzw. beim Speichern abgewiesen. Änderungen nach der Versandbestätigung stoppen den Versand dieser Aufgabe.
- Ungeprüfte, veraltete, abgesagte, ausgeblendete, nicht eigene und bereits exportierte Aufgaben werden auch in der Daten-/Versandschicht ausgeschlossen. Ungültige Termine oder Tags werden abgewiesen. Bereits verbuchte CSV-Exporte bleiben für direkten Versand gesperrt.
- Vor neuem Versand werden Konto und verfügbare Projekte erneut abgefragt. Ein gelöschtes oder nicht mehr zugängliches Projekt erzeugt keine Ersatzaufgabe im Eingang, sondern eine sichtbare Fehlermeldung.
- Der Auftrag mit stabiler UUID wird vor dem ersten Aufgaben-POST gespeichert und an die ID des Todoist-Kontos gebunden. Netzwerkprobleme behalten exakt denselben Auftrag. Ein Wechsel des API-Keys zu einem anderen Konto darf einen offenen Auftrag nicht dort wiederholen. Alte offene Aufträge ohne eindeutige Kontobindung erfordern eine manuelle Prüfung in Todoist.
- Eindeutige Ablehnungen geben den Entwurf zur Korrektur frei. Nach einer teilweise erfolgreichen Übertragung bleiben erfolgreiche Aufgaben mit ihrer Todoist-ID gespeichert. Ein unklarer fehlgeschlagener Auftrag bleibt einzeln wiederholbar; spätere nicht versuchte Aufgaben bleiben offen und können anschließend neu ausgewählt werden.

## Datenschutz und Speicherung

Der API-Key verbleibt im macOS-Schlüsselbund. In der lokalen Inbox werden nur die Kontokennung des jeweiligen Versandauftrags, Meeting-Vorgaben, Textentwürfe und Exportbelege gespeichert. Es werden keine Schlüssel in UserDefaults, Projektdateien, CSV oder Logs geschrieben. Zugangsdaten liegen nur während der erforderlichen HTTPS-Anfragen im Arbeitsspeicher. Weiterleitungen sind deaktiviert.

Aufgaben werden ausschließlich nach Bestätigung mit Titel, Terminen, Tags, Meetingname, kurzen Belegen und gegebenenfalls persönlichen Notizen übertragen. Kein Audio, keine biometrischen Merkmale und kein vollständiges Transkript werden gesendet. „Projekte und Tags laden“ sowie „Verbindung prüfen“ sind authentifizierte Lesezugriffe auf Todoist. Ohne API-Key kann die lokale Inbox weiter benutzt werden.

## Prüfung

Regressionstests verwenden temporäre Daten und simulierte Antworten für Kontoabfrage, Projekte, Tags und Aufgabenanlage. Geprüft werden Meeting-Grenzen, eigene/fremde Aufgaben, bulkweise Projekt-/Tagänderung, unveränderte Datumsfelder, veraltete Editoren, geänderte Zuständigkeiten, doppelte Sprechernamen, neue Aufgaben nach erneuter Zusammenfassung, Key-/Kontowechsel, alte offene Aufträge, gelöschte Projekte, Teilfehler, wiederholter Versand und ungültige Tags/Termine. Das neue Fenster wird mit künstlichen Daten gerendert und visuell kontrolliert.

Ein tatsächlicher Kontotest mit dem vom Nutzer eingetragenen API-Key bleibt erforderlich. Die Entwicklungstests speichern keinen echten Schlüssel und legen keine echten Todoist-Aufgaben an.

Technische Grundlage: [aktuelle Todoist API v1](https://developer.todoist.com/api/v1/).

Prüfstand: **197 XCTest-Tests, 12 bewusst ausgelassen, 0 Fehler**; darunter 18 neue Meeting-/Todoist-Policy-Tests. **56 zusätzliche Kernprüfungen bestanden.** Die vollständige Suite enthält die lokale LLM-Prüfung und die synthetische Oberflächendarstellung.

### Korrektur der Schlüsseleingabe

Das zunächst randlose SwiftUI-Feld wurde durch ein klar umrandetes natives macOS-Passwortfeld mit Einfügen-Button ersetzt. ⌘V und ⌘A funktionieren direkt über das Feld, auch ohne Bearbeiten-Menü der Menüleisten-App. Der Inhalt bleibt verdeckt und wird weiterhin nur nach Verbindungsprüfung im Schlüsselbund gespeichert. Vier neue UI-Tests prüfen echte Texteingabe und Bindung, Tastatur-Einfügen über das Fenster, deaktivierte Eingabe ohne Zwischenablagenzugriff und die Darstellung im dunklen Modus. Zusammen mit den Meeting-/Todoist-Tests: 34 Tests ohne Fehler. Alle Eingabewerte sind synthetisch; Tests lesen oder verändern die Benutzerzwischenablage nicht.
