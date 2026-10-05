import AVFoundation

/// Reads Mandarin aloud with Apple's built-in voice (free, works offline).
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()

    func say(_ text: String, slow: Bool = false) {
        synthesizer.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        AlarmSound.shared.hold(for: slow ? 3.5 : 2.5)
        // Don't take over the session while the mic is recording.
        if !LiveTranscriber.isRecording {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.6 : 0.85)
        synthesizer.speak(utterance)
    }
}
