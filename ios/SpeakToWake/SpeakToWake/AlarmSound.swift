import AVFoundation
import AudioToolbox

/// Keeps an alarm sound going inside the challenge until it's passed, the way
/// Alarmy does. (Tapping Speak silences the system alarm, so without this the
/// challenge screen would be quiet.)
///
/// The sound pauses while the mic listens (so the recognizer doesn't hear it) and
/// while a word is read aloud, then comes back.
final class AlarmSound {
    static let shared = AlarmSound()

    private var player: AVAudioPlayer?
    private var isOn = false
    private var pauseReasons: Set<String> = []
    private var holdTask: Task<Void, Never>?
    private var vibrateTask: Task<Void, Never>?

    func start() {
        isOn = true
        update()
    }

    func stop() {
        isOn = false
        pauseReasons.removeAll()
        holdTask?.cancel()
        update()
    }

    /// Pause for a reason ("listening", "speaking"); plays again once no reasons are left.
    func setPaused(_ paused: Bool, reason: String) {
        if paused {
            pauseReasons.insert(reason)
        } else {
            pauseReasons.remove(reason)
        }
        update()
    }

    /// Quiet for a few seconds, e.g. while the app reads a word aloud.
    func hold(for seconds: Double) {
        guard isOn else { return }
        setPaused(true, reason: "speaking")
        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            setPaused(false, reason: "speaking")
        }
    }

    private func update() {
        guard isOn && pauseReasons.isEmpty && !LiveTranscriber.isRecording else {
            player?.pause()
            vibrateTask?.cancel()
            vibrateTask = nil
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[AlarmSound] session error: \(error)")
        }
        if player == nil {
            do {
                player = try AVAudioPlayer(data: Self.beepPattern())
                player?.numberOfLoops = -1  // forever, until stopped
            } catch {
                print("[AlarmSound] player error: \(error)")
            }
        }
        player?.volume = 1
        player?.play()
        startVibrating()
    }

    /// A buzz with every round of beeps, in case the phone is under a pillow.
    private func startVibrating() {
        guard vibrateTask == nil else { return }
        vibrateTask = Task {
            while !Task.isCancelled {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(for: .seconds(Self.patternSeconds))
            }
        }
    }

    /// Length of one round of beeps, used to time the vibration.
    private static let patternSeconds = 4 * (0.14 + 0.06) + 0.4

    /// Four harsh beeps and a short pause, as a WAV file in memory.
    ///
    /// Ears are most sensitive around 2-4 kHz (smoke alarms use about 3 kHz),
    /// and a buzzy, clipped wave sounds much louder than a pure tone at the same
    /// volume. Alternating two pitches makes it harder to tune out.
    private static func beepPattern(sampleRate: Int = 44_100) -> Data {
        var samples: [Int16] = []
        func tone(_ frequency: Double, _ seconds: Double) {
            let count = Int(seconds * Double(sampleRate))
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                let fade = min(1, min(t, seconds - t) / 0.005)  // avoid clicks
                let wave = sin(2 * .pi * frequency * t) * 3  // overdrive, then clip: buzzy and loud
                samples.append(Int16(max(-1, min(1, wave)) * 0.98 * fade * Double(Int16.max)))
            }
        }
        func silence(_ seconds: Double) {
            samples += repeatElement(0, count: Int(seconds * Double(sampleRate)))
        }
        for i in 0..<4 {
            tone(i.isMultiple(of: 2) ? 2_800 : 3_300, 0.14)
            silence(0.06)
        }
        silence(0.4)

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let dataSize = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))  // bytes per second
        append(UInt16(2))  // bytes per sample
        append(UInt16(16))  // bits per sample
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        for sample in samples { append(sample) }
        return data
    }
}
