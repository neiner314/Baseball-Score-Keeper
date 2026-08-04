import AVFoundation

/// Speaks confirmations so the phone can stay in a pocket.
///
/// Utterances are short and interruptible — a scorer tapping quickly should
/// hear the latest call, not a backlog of the last four pitches.
@MainActor
final class Announcer {
    static let shared = Announcer()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func say(_ text: String) {
        guard !text.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        configureSessionForMixing()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Ducks rather than interrupts, so the game audio the scorer is listening
    /// to keeps playing underneath.
    private func configureSessionForMixing() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .mixWithOthers]
        )
        try? session.setActive(true, options: [])
    }
}
