import SwiftUI

/// Phase 1 debug screen: is Mandarin speech recognition available on this phone?
struct SpeechCheckView: View {
    @State private var model = SpeechModelManager()

    var body: some View {
        NavigationStack {
            List {
                Section("Mandarin (zh-CN)") {
                    statusRow
                    if let locale = model.matchedLocale {
                        LabeledContent("Matched locale", value: locale.identifier(.bcp47))
                    }
                    if model.state == .notInstalled {
                        Button("Download Mandarin model") {
                            Task { await model.download() }
                        }
                    }
                    if model.state == .downloading {
                        ProgressView(value: model.progress)
                    }
                }

                Section("Chinese locales on this phone") {
                    if model.chineseLocales.isEmpty {
                        Text("None found").foregroundStyle(.secondary)
                    }
                    ForEach(model.chineseLocales, id: \.self) { Text($0) }
                }

                Section {
                    LabeledContent("Languages supported", value: "\(model.supportedCount)")
                    Button("Check again") {
                        Task { await model.check() }
                    }
                }
            }
            .navigationTitle("Speech check")
            .task { await model.check() }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.state {
        case .checking:
            Label("Checking…", systemImage: "hourglass")
        case .unsupported:
            Label("Not supported on this phone", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .notInstalled:
            Label("Supported, model not downloaded", systemImage: "arrow.down.circle")
                .foregroundStyle(.orange)
        case .downloading:
            Label("Downloading…", systemImage: "arrow.down.circle")
        case .installed:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    SpeechCheckView()
}
