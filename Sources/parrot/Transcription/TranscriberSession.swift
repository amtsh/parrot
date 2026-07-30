import Foundation

/// Owns the currently active transcriber and allows swapping models
/// mid-session. `switchTo` only replaces the active transcriber after the new
/// one has successfully warmed up, so a failed switch leaves the prior model
/// working.
actor TranscriberSession {
    private var current: Transcriber

    init(initial: Transcriber) {
        self.current = initial
    }

    var modelID: String {
        current.modelID
    }

    func transcribe(_ audio: [Float]) async throws -> String {
        try await current.transcribe(audio)
    }

    func switchTo(_ model: TranscriptionModel) async throws {
        let next = WhisperKitTranscriber(model: model)
        try await next.warmUp()
        current = next
    }
}
