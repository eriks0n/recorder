# Modell- und Abhängigkeitenstand

Stand 2026-10-25. Quellen sind die jeweiligen Repository-Manifeste und Hugging-Face-Modellmetadaten. Modell-Downloads wurden bei der Implementierung nicht als erfolgreich getestet ausgegeben.

| Komponente | Fester Stand | Angegebene Lizenz |
|---|---|---|
| cjonesde/recorder | f1ba832a52ef600d2be94bb549900d42845f1632 | MIT |
| argmaxinc/WhisperKit | 1.1.0; exakte Revision in Package.resolved | MIT |
| argmaxinc/whisperkit-coreml | 0f63a7800b00dd0226abd051b906c246e1907482 | MIT laut Modellmetadaten |
| argmaxinc/speakerkit-coreml | 556fc52a13327837688f02289457cded017802e9 | CC BY 4.0 laut Modellmetadaten |
| mlx-swift-lm | 2.29.3 (optionaler Build) | MIT |
| mlx-community/Qwen3-4B-4bit | 4dcb3d101c2a062e5c1d4bb173588c54ea6c4d25 | Apache 2.0 laut Modellmetadaten |

WhisperKit-Modelle basieren auf OpenAIs Whisper; SpeakerKit exportiert pyannote-Modelle. Quellen und jeweilige Modellkarten: [WhisperKit](https://github.com/argmaxinc/WhisperKit/tree/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d), [Whisper-Modelle](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/0f63a7800b00dd0226abd051b906c246e1907482), [SpeakerKit-Modelle](https://huggingface.co/argmaxinc/speakerkit-coreml/tree/556fc52a13327837688f02289457cded017802e9), [Qwen3](https://huggingface.co/mlx-community/Qwen3-4B-4bit/tree/4dcb3d101c2a062e5c1d4bb173588c54ea6c4d25).

Die genaue Dateiliste und alle Tokenizerrevisionen liegen in `Sources/Recorder/Resources/models.json`. Whisper-Varianten reichen laut Fork-Katalog von etwa 110 bis 630 MB; der LLM-Snapshot umfasst laut Hub-Metadaten rund 2,27 GB, das gesamte SpeakerKit-Repository rund 30 MB. Tatsächliche Teilmengen, Latenz und RAM-Verbrauch müssen beim Download/Modelltest gemessen werden. Die Zahlen sind keine gemessenen Download- oder Laufzeitwerte dieser App.

Downloads verwenden ausschließlich feste Snapshot-URLs über HTTPS. Nach vollständiger Installation wird ein SHA-256-Dateimanifest geschrieben und vor dem Laden geprüft. Das erkennt nachträgliche Beschädigung, ist aber keine unabhängige Signatur des Modellherstellers. Keine ausführbaren Modelldateien oder Remote-Code-Ausführung werden unterstützt. Tokenizer und Modelle werden lokal geladen; der mögliche Netzwerk-Fallback des WhisperKit-Tokenizer-Helfers wird durch den lokalen Adapter umgangen.

Das kleine Qwen-Modell ist ein vorläufiger Kandidat. Ein Vergleich mit einer größeren Größenklasse ist ohne Testtranskript und Metal-Werkzeuge noch offen. Die Entscheidung ist daher ausdrücklich nicht als P0-Modellabnahme zu verstehen.

## Laufende MLX-Integration

Xcode 27.1 (27A9275) und Metal Toolchain 27A266a (Compiler 32023.921.6) sind installiert. Der vorhandene Qwen-Snapshot wurde über das Dateimanifest geprüft (10 Dateien, ca. 2,28 GB). Der lokale Inferenztest mit einem künstlichen deutschen Meeting lief erfolgreich und erzeugte beide expliziten Aufgaben mit gültigen Belegen; eine genannte Frist blieb erhalten, eine fehlende Frist leer. Das ist ein Funktionstest eines Kandidaten, kein Vergleich gegen größere Modelle und keine Qualitätszusage für reale Meetings.
