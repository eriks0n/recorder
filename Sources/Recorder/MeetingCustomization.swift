import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

/// A vocabulary biases recognition; it never rewrites homophones after decoding.
enum TranscriptionVocabulary {
    static let maxCharacters = 2000
    static func terms(_ text: String) -> [String] {
        var seen = Set<String>()
        return String(text.prefix(maxCharacters)).components(separatedBy: .newlines).compactMap {
            let term = $0.components(separatedBy: .controlCharacters).joined().trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { return nil }
            return term
        }
    }
    #if canImport(WhisperKit)
    static func promptTokens(_ text: String, tokenizer: WhisperTokenizer?) -> [Int]? {
        guard let tokenizer else { return nil }
        var tokens: [Int] = []
        for term in terms(text) {
            let candidate = tokenizer.encode(text: " " + term + ",").filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            // Keep complete terms, in priority order, within Whisper's prompt budget.
            guard tokens.count + candidate.count <= 200 else { break }
            tokens += candidate
        }
        return tokens.isEmpty ? nil : tokens
    }
    #endif
}

/// Literal, single-pass substitution. Templates never become model instructions or executable code.
enum SummaryTemplate {
    static let maxCharacters = 20000
    static let standard = """
    # {{meeting_title}}

    ## Zusammenfassung
    {{executive_summary}}

    ## Themen
    {{topics}}

    ## Aufgaben
    {{action_items}}

    ## Nächste Schritte
    {{next_steps}}
    """
    static let placeholders = ["meeting_title", "executive_summary", "topics", "action_items", "next_steps"]
    static func validate(_ text: String) throws {
        guard text.count <= maxCharacters else { throw LocalError.message("Das Template darf höchstens 20.000 Zeichen enthalten.") }
        let pattern = try NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
        let range = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: range) {
            let name = (text as NSString).substring(with: match.range(at: 1))
            guard placeholders.contains(name) else { throw LocalError.message("Unbekannter Template-Platzhalter: {{\(name)}}") }
        }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.contains("{{executive_summary}}") else {
            throw LocalError.message("Das Template muss {{executive_summary}} enthalten. Leer lassen verwendet das Standardlayout.")
        }
    }
    static func render(_ template: String, values: [String: String]) -> String {
        // Do not interpret placeholder-looking content inside meeting text a second time.
        let regex = try! NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
        let source = template as NSString
        var output = "", offset = 0
        for match in regex.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: offset, length: match.range.location - offset))
            output += values[source.substring(with: match.range(at: 1))] ?? source.substring(with: match.range)
            offset = match.range.location + match.range.length
        }
        return output + source.substring(from: offset)
    }
}
