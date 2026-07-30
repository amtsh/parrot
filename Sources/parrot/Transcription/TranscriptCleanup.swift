#if canImport(FoundationModels)
import FoundationModels
#endif

/// Filler-word removal and punctuation/capitalization cleanup for dictated
/// text, using Apple's on-device Foundation Models — no network call, no
/// per-token cost, nothing leaves the machine.
///
/// The factory returns a plain closure rather than exposing the
/// `@available(macOS 26.0, *)`-restricted session type directly, so callers
/// on the package's macOS 14+ deployment target can hold the result
/// uniformly without themselves needing availability guards everywhere.
///
/// `FoundationModels` only exists in the macOS 26 SDK — building with an
/// older Xcode/SDK (as CI's runner image may have) can't even find the
/// module, which is a compile-time problem `#available` alone can't solve.
/// `#if canImport` degrades this to a no-op on those toolchains instead of
/// failing to compile; the feature simply won't exist in a binary built
/// that way, regardless of what OS it later runs on.
enum TranscriptCleanupFactory {
    /// Returns a cleanup function if Apple Intelligence's on-device model is
    /// available on this Mac, or nil otherwise (older macOS, ineligible
    /// hardware, Apple Intelligence not enabled, or a toolchain that doesn't
    /// have FoundationModels at all).
    static func make() -> ((String) async -> String)? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        return { text in
            guard !text.isEmpty else { return text }
            do {
                let response = try await session.respond(to: text)
                let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return isSane(cleaned, comparedTo: text) ? cleaned : text
            } catch {
                return text
            }
        }
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    private static let instructions = """
    You clean up raw speech-to-text dictation transcripts. Remove filler \
    words (um, uh, like, you know, etc.) and fix capitalization and \
    punctuation. Do not change the wording or meaning, do not summarize, \
    and do not add any commentary. Reply with only the cleaned text.
    """

    /// A crude but effective guard against a hallucinated or refused
    /// response: cleanup should never wildly change the transcript's length.
    /// Dictation should never come back empty or mangled because this step
    /// misbehaved — when in doubt, fall back to the raw transcript.
    private static func isSane(_ cleaned: String, comparedTo original: String) -> Bool {
        guard !cleaned.isEmpty else { return false }
        let originalWords = original.split(separator: " ").count
        guard originalWords > 0 else { return true }
        let cleanedWords = cleaned.split(separator: " ").count
        let ratio = Double(cleanedWords) / Double(originalWords)
        return ratio > 0.5 && ratio < 1.5
    }
    #endif
}
