import AVFoundation
import MediaPlayer
import SwiftUI

/// Apps can read the phone's volume but not change it (no public API), so the
/// app asks the user to turn it up, with Apple's own volume slider right there.
@Observable
final class VolumeMonitor {
    /// Below this, the in-app alarm sound may be too quiet to wake you.
    static let lowThreshold: Float = 0.5

    private(set) var volume: Float = AVAudioSession.sharedInstance().outputVolume
    private var observation: NSKeyValueObservation?

    var isLow: Bool { volume < Self.lowThreshold }

    func start() {
        let session = AVAudioSession.sharedInstance()
        // An active session is needed to get volume updates. Ambient mixes with
        // other audio, so opening the Alarm tab doesn't stop your music.
        if !LiveTranscriber.isRecording {
            try? session.setCategory(.ambient)
            try? session.setActive(true)
        }
        volume = session.outputVolume
        observation = session.observe(\.outputVolume) { [weak self] session, _ in
            let volume = session.outputVolume
            Task { @MainActor in self?.volume = volume }
        }
    }

    func stop() {
        observation = nil
    }
}

/// "Your volume is at 20%" plus the system slider. Shown in the Alarm tab.
struct VolumeCheckView: View {
    @State private var monitor = VolumeMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if monitor.isLow {
                Label("Your volume is at \(Int(monitor.volume * 100))%. Turn it up so the alarm wakes you.",
                      systemImage: "speaker.slash.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline.bold())
            } else {
                Label("Volume \(Int(monitor.volume * 100))%", systemImage: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            SystemVolumeSlider()
                .frame(height: 34)
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

/// Apple's official volume slider (MPVolumeView). Moving it changes the phone's volume.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.showsVolumeSlider = true
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
