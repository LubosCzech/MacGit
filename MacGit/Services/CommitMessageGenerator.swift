import Foundation
import FoundationModels
import GitKit

/// Návrh commit zprávy pomocí systémového modelu Apple Intelligence (běží na zařízení).
@MainActor
enum CommitMessageGenerator {
    /// Rozpočet na přehled změn. Kontext modelu je ~4 096 tokenů včetně instrukcí a odpovědi.
    static let summaryCharacterLimit = 7_000

    enum Status: Equatable {
        case available
        case unavailable(String)
    }

    static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Zapni Apple Intelligence v Nastavení systému → Apple Intelligence a Siri.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("Tento Mac nepodporuje Apple Intelligence.")
        case .unavailable(.modelNotReady):
            return .unavailable("Model Apple Intelligence zatím není připravený – stahuje se, nebo ještě není v tvém regionu dostupný.")
        case .unavailable:
            return .unavailable("Apple Intelligence není dostupná.")
        }
    }

    @Generable
    struct Suggestion {
        @Guide(description: "Commit subject line in English, imperative mood (e.g. 'Add signature verification'), at most 72 characters, no trailing period.")
        var summary: String

        @Guide(description: "Optional commit body in English: 1-4 short lines or bullet points explaining what changed and why. Empty string when the change is trivial.")
        var body: String
    }

    private static let instructions = """
    You write concise git commit messages for a developer.
    Describe the intent of the change, not a list of files.
    Use the imperative mood in the subject line and keep it under 72 characters.
    Follow the style of the recent commit subjects when they are provided.
    Never invent changes that are not in the provided summary.
    """

    /// Vygeneruje návrh a průběžně hlásí rozpracovaný text.
    static func suggest(
        summary: String,
        branch: String?,
        recentSubjects: [String],
        onPartial: @escaping (String, String) -> Void
    ) async throws -> (summary: String, body: String) {
        var prompt = ""
        if let branch { prompt += "Branch: \(branch)\n" }
        if !recentSubjects.isEmpty {
            prompt += "Recent commit subjects:\n" + recentSubjects.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        prompt += "\n" + summary + "\n\nWrite the commit message for these changes."

        let session = LanguageModelSession(instructions: instructions)
        let stream = session.streamResponse(to: prompt, generating: Suggestion.self, options: GenerationOptions(temperature: 0.3))
        var last: (String, String) = ("", "")
        for try await snapshot in stream {
            last = (snapshot.content.summary ?? "", snapshot.content.body ?? "")
            onPartial(last.0, last.1)
        }
        return (last.0.trimmingCharacters(in: .whitespacesAndNewlines), last.1.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func message(for error: Error) -> String {
        switch error {
        case LanguageModelSession.GenerationError.exceededContextWindowSize:
            "Změny jsou na model příliš velké. Zkus vybrat méně souborů."
        case LanguageModelSession.GenerationError.guardrailViolation:
            "Model odmítl obsah změn zpracovat."
        case LanguageModelSession.GenerationError.unsupportedLanguageOrLocale:
            "Model nepodporuje jazyk obsahu změn."
        case LanguageModelSession.GenerationError.assetsUnavailable:
            "Model Apple Intelligence teď není k dispozici."
        default:
            "Návrh zprávy se nepodařil: \(error.localizedDescription)"
        }
    }
}
