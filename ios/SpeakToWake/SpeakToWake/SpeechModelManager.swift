import Foundation
import Speech

/// Checks whether this phone can transcribe Mandarin on-device, and downloads
/// the speech model if it isn't installed yet.
@Observable
final class SpeechModelManager {
    enum State: Equatable {
        case checking
        case unsupported
        case notInstalled
        case downloading
        case installed
        case failed(String)
    }

    let wanted = Locale(identifier: "zh-CN")

    private(set) var state: State = .checking
    private(set) var matchedLocale: Locale?
    private(set) var supportedCount = 0
    private(set) var chineseLocales: [String] = []
    private(set) var progress: Double = 0

    func check() async {
        state = .checking
        let supported = await SpeechTranscriber.supportedLocales
        supportedCount = supported.count
        chineseLocales = supported
            .map { $0.identifier(.bcp47) }
            .filter { $0.hasPrefix("zh") || $0.hasPrefix("yue") }
            .sorted()

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            state = .unsupported
            return
        }
        matchedLocale = locale

        let installed = await SpeechTranscriber.installedLocales
        let isInstalled = installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        state = isInstalled ? .installed : .notInstalled
    }

    func download() async {
        guard let locale = matchedLocale else { return }
        state = .downloading
        progress = 0
        do {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: []
            )
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                // The request reports progress through a Foundation Progress object; poll it for the UI.
                let watcher = Task {
                    while !Task.isCancelled {
                        progress = request.progress.fractionCompleted
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                defer { watcher.cancel() }
                try await request.downloadAndInstall()
            }
            await check()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
