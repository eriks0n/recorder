import Foundation
import CryptoKit

enum AudioChannel: String, Codable { case desktop, microphone }
struct MeetingRecord: Codable, Identifiable, Equatable {
    var schemaVersion = 1
    var id = UUID()
    var scope = "default"
    var startedAt: Date
    var title: String?
    var attendees: [String] = []
    var attendeeEmails: [String] = []
    var hasCalendarEvent = false
}
struct TranscriptWord: Codable, Equatable {
    var text: String
    var start: Double
    var end: Double
    var channel: AudioChannel
    var speakerID: String
    var overlap = false
}
struct SpeakerTurn: Codable, Identifiable, Equatable {
    var id: String
    var speakerID: String
    var channel: AudioChannel
    var start: Double
    var end: Double
    var text: String
    var overlap: Bool
}
enum AssignmentStatus: String, Codable { case unknown, proposed, confirmed, rejected }
struct SpeakerAssignment: Codable, Identifiable {
    var id: String
    var profileID: UUID?
    var name: String?
    var similarity: Double?
    var status: AssignmentStatus = .unknown
}
struct MeetingTranscript: Codable {
    var schemaVersion = 1
    var meeting: MeetingRecord
    var modelVersion: String
    var words: [TranscriptWord]
    var turns: [SpeakerTurn]
    var assignments: [SpeakerAssignment] = []
    // Embeddings remain in memory until explicit enrollment, never in transcript exports.
    var hash: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    func label(_ speakerID: String) -> String {
        if let a = assignments.first(where: { $0.id == speakerID }), a.status == .confirmed, let name = a.name { return name }
        return speakerID
    }
    var markdown: String {
        "# \(meeting.title ?? "Transkript")\n\n" + turns.map {
            "[\(Self.timestamp($0.start))] **\(label($0.speakerID))** (\($0.id), \($0.channel.rawValue))\($0.overlap ? " [Überlappung/unklar]" : ""): \($0.text)"
        }.joined(separator: "\n\n") + "\n"
    }
    static func timestamp(_ seconds: Double) -> String {
        let s = max(0, Int(seconds)); return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
struct SpeakerInterval {
    var id: String
    var start: Double
    var end: Double
    var channel: AudioChannel
}
enum TranscriptAssembler {
    static func assemble(words: [TranscriptWord], intervals: [SpeakerInterval]) -> ([TranscriptWord], [SpeakerTurn]) {
        let assigned = words.sorted { $0.start < $1.start }.map { word -> TranscriptWord in
            var word = word
            let candidates = intervals.filter { $0.channel == word.channel && min($0.end, word.end) > max($0.start, word.start) }
                .sorted { min($0.end, word.end) - max($0.start, word.start) > min($1.end, word.end) - max($1.start, word.start) }
            word.speakerID = candidates.first?.id ?? "Unbekannt-\(word.channel.rawValue)"
            word.overlap = candidates.count > 1 || intervals.contains {
                $0.channel != word.channel && min($0.end, word.end) > max($0.start, word.start)
            }
            return word
        }
        var turns: [SpeakerTurn] = []
        for w in assigned {
            if let last = turns.last, last.speakerID == w.speakerID, last.channel == w.channel,
               last.overlap == w.overlap, w.start - last.end < 1.5, w.end - last.start < 25 {
                turns[turns.count - 1].text += " " + w.text
                turns[turns.count - 1].end = max(last.end, w.end)
            } else {
                turns.append(SpeakerTurn(id: "T\(turns.count + 1)", speakerID: w.speakerID, channel: w.channel,
                                         start: w.start, end: w.end, text: w.text, overlap: w.overlap))
            }
        }
        return (assigned, turns)
    }
}

enum LocalError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}
