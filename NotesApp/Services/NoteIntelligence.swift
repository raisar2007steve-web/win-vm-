import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device writing assistant.
///
/// Uses Apple's Foundation Models framework when the device, OS and language
/// support it. Otherwise it falls back to deterministic local heuristics, which
/// are real (if simpler) implementations — never mocks and never a network call.
@MainActor
@Observable
final class NoteIntelligence {
    enum Action: String, CaseIterable, Identifiable {
        case summarize
        case proofread
        case rewrite
        case extractTasks
        case generateTitle
        case suggestTags

        var id: String { rawValue }

        var title: String {
            switch self {
            case .summarize: return "Summarize"
            case .proofread: return "Proofread"
            case .rewrite: return "Rewrite Clearly"
            case .extractTasks: return "Extract Tasks"
            case .generateTitle: return "Suggest Title"
            case .suggestTags: return "Suggest Tags"
            }
        }

        var systemImage: String {
            switch self {
            case .summarize: return "text.line.first.and.arrowtriangle.forward"
            case .proofread: return "checkmark.seal"
            case .rewrite: return "arrow.triangle.2.circlepath"
            case .extractTasks: return "checklist"
            case .generateTitle: return "character.cursor.ibeam"
            case .suggestTags: return "number"
            }
        }

        var instructions: String {
            switch self {
            case .summarize:
                return "Summarize the note in at most three sentences. Keep concrete facts. Return only the summary."
            case .proofread:
                return "Correct spelling, grammar and punctuation. Preserve meaning, tone and formatting. Return only the corrected text."
            case .rewrite:
                return "Rewrite the note so it is clearer and more concise while keeping every fact. Return only the rewritten text."
            case .extractTasks:
                return "List the actionable tasks in the note as short imperative bullet points. Return only the bullets."
            case .generateTitle:
                return "Write a specific title of at most eight words for this note. Return only the title, without quotes."
            case .suggestTags:
                return "Suggest three or four lowercase topical tags, comma separated, no hashes. Return only the tags."
            }
        }
    }

    struct Outcome {
        let action: Action
        let text: String
        let usedOnDeviceModel: Bool
    }

    private(set) var isRunning = false
    private(set) var lastOutcome: Outcome?
    var lastError: String?

    /// True when Apple's on-device model can actually run on this device.
    var isFoundationModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    var availabilityDescription: String {
        if isFoundationModelAvailable {
            return "Apple Foundation Models on this device"
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple Foundation Models on this device"
            case .unavailable(let reason):
                return "On-device model unavailable (\(String(describing: reason))). Using built-in local processing."
            @unknown default:
                return "Using built-in local processing."
            }
        }
        #endif
        return "Built-in local processing (Foundation Models requires iOS 26 or later on a supported device)."
    }

    func perform(_ action: Action, on text: String) async -> Outcome? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "There is nothing to work with yet."
            return nil
        }
        isRunning = true
        lastError = nil
        defer { isRunning = false }

        if isFoundationModelAvailable, let generated = await runFoundationModel(action, text: trimmed) {
            let outcome = Outcome(action: action, text: generated, usedOnDeviceModel: true)
            lastOutcome = outcome
            return outcome
        }

        let fallback = HeuristicWriting.process(action, text: trimmed)
        let outcome = Outcome(action: action, text: fallback, usedOnDeviceModel: false)
        lastOutcome = outcome
        return outcome
    }

    private func runFoundationModel(_ action: Action, text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: action.instructions)
                let response = try await session.respond(to: text)
                let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return content.isEmpty ? nil : content
            } catch {
                // Fall through to local processing; never surface note text in errors.
                lastError = "On-device model could not respond. Used built-in processing instead."
                return nil
            }
        }
        #endif
        return nil
    }
}

/// Deterministic, offline fallbacks. Simple heuristics, but genuinely functional:
/// sentence-ranked summaries, conservative typo fixes, task extraction and keyword tags.
enum HeuristicWriting {
    static func process(_ action: NoteIntelligence.Action, text: String) -> String {
        switch action {
        case .summarize:
            return summarize(text)
        case .proofread:
            return proofread(text)
        case .rewrite:
            return rewrite(text)
        case .extractTasks:
            return extractTasks(text)
        case .generateTitle:
            return title(from: text)
        case .suggestTags:
            return tags(from: text)
        }
    }

    static func sentences(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .flatMap { line in
                line.split(separator: ".", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
            }
            .filter { !$0.isEmpty }
    }

    static func summarize(_ text: String) -> String {
        let all = sentences(in: text)
        guard all.count > 2 else { return text }
        let scores = all.map { sentence -> (String, Int) in
            let words = sentence.split(separator: " ").map { $0.lowercased() }
            let unique = Set(words).count
            let numbers = words.contains { $0.first?.isNumber == true } ? 2 : 0
            return (sentence, unique + numbers)
        }
        let top = scores.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
        // Preserve original order for readability.
        let ordered = all.filter { top.contains($0) }
        let summary = ordered.joined(separator: ". ")
        return summary.hasSuffix(".") ? summary : summary + "."
    }

    static func proofread(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("  ", " "),
            (" ,", ","),
            (" .", "."),
            ("teh ", "the "),
            ("recieve", "receive"),
            ("seperate", "separate"),
            ("definately", "definitely"),
            ("occured", "occurred"),
            ("alot", "a lot"),
            (" i ", " I ")
        ]
        for (lhs, rhs) in replacements {
            result = result.replacingOccurrences(of: lhs, with: rhs, options: [.caseInsensitive])
        }
        var lines = result.components(separatedBy: .newlines)
        for index in lines.indices {
            var line = lines[index]
            if let first = line.first, first.isLowercase, !line.hasPrefix("i ") {
                line = first.uppercased() + line.dropFirst()
            }
            if !line.isEmpty, !line.hasSuffix("."), !line.hasSuffix("!"), !line.hasSuffix("?"), !line.hasSuffix(":"),
               !line.hasSuffix(")"), !line.hasSuffix("```") {
                line += "."
            }
            lines[index] = line
        }
        return lines.joined(separator: "\n")
    }

    static func rewrite(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "really ", with: "")
            .replacingOccurrences(of: "very ", with: "")
            .replacingOccurrences(of: "just ", with: "")
            .replacingOccurrences(of: "basically ", with: "")
        let trimmedSentences = sentences(in: cleaned).map { sentence in
            sentence.split(separator: " ").prefix(28).joined(separator: " ")
        }
        return trimmedSentences.joined(separator: ". ") + (trimmedSentences.isEmpty ? "" : ".")
    }

    static func extractTasks(_ text: String) -> String {
        let cues = ["need to", "todo", "to do", "must", "should", "remember to", "follow up", "next:", "action"]
        let candidates = text.components(separatedBy: .newlines)
            .flatMap { $0.split(separator: ".").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && cues.contains { line.lowercased().contains($0) }
            }
        if candidates.isEmpty {
            let fallback = sentences(in: text).prefix(3)
            return fallback.map { "- " + $0 }.joined(separator: "\n")
        }
        return candidates.map { "- " + $0 }.joined(separator: "\n")
    }

    static func title(from text: String) -> String {
        let first = sentences(in: text).first ?? text
        let words = first.split(separator: " ").prefix(8).joined(separator: " ")
        return words.isEmpty ? "Untitled Note" : words
    }

    static func tags(from text: String) -> String {
        let stopWords: Set<String> = ["the", "and", "for", "with", "that", "this", "from", "have", "will", "your",
                                      "about", "into", "they", "them", "then", "when", "what", "there", "here",
                                      "note", "notes", "just", "some", "more", "very", "should", "would", "could"]
        var counts: [String: Int] = [:]
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            let token = String(word)
            guard token.count > 3, !stopWords.contains(token) else { continue }
            counts[token, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(4).map(\.key).joined(separator: ", ")
    }
}
