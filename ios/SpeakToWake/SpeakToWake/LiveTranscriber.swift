import AVFoundation
import Speech

/// Listens to the mic and turns Mandarin speech into text as you talk.
///
/// The recognizer sends two kinds of results: "volatile" ones (its current
/// best guess, which keeps changing) and "final" ones (locked in).
@Observable
final class LiveTranscriber {
    private(set) var finalText = ""
    private(set) var volatileText = ""
    private(set) var isListening = false
    private(set) var errorMessage: String?

    var transcript: String { finalText + volatileText }

    /// True while any transcriber has the mic, so sounds don't play into it.
    static private(set) var isRecording = false

    private let mic = MicCapture()
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// `hints` are words the recognizer should expect. Without them it guesses the
    /// most common word that fits the sound (shuì can come out as 对 duì).
    func start(locale: Locale, hints: [String] = []) async {
        guard !isListening else { return }
        errorMessage = nil
        finalText = ""
        volatileText = ""

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access is off. Turn it on in Settings → Privacy & Security → Microphone."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)

            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if !hints.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = hints
                try await analyzer.setContext(context)
            }
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

            resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            finalText += text
                            volatileText = ""
                        } else {
                            volatileText = text
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            try await analyzer.start(inputSequence: inputSequence)
            try mic.start(targetFormat: format) { buffer in
                inputBuilder.yield(AnalyzerInput(buffer: buffer))
            }

            self.analyzer = analyzer
            self.inputBuilder = inputBuilder
            isListening = true
            Self.isRecording = true
        } catch {
            errorMessage = error.localizedDescription
            await stop()
        }
    }

    func stop() async {
        mic.stop()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value  // wait for the last final result to arrive
        analyzer = nil
        inputBuilder = nil
        resultsTask = nil
        isListening = false
        Self.isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
