import SwiftUI

/// A language Mingo teaches, or will. Mandarin, Korean and Japanese have words;
/// the others show as "Coming soon" so the picker reflects the plan.
struct LanguageOption: Identifiable, Hashable {
    let id: String          // locale code, matches the word data files (words.<id>.json)
    let name: String
    let native: String
    let flag: String
    /// The level system its sections follow: "HSK" for Mandarin. Korean and Japanese
    /// use plain "Level", since our sections don't line up with TOPIK or JLPT.
    let levels: String
    let available: Bool

    static let all: [LanguageOption] = [
        LanguageOption(id: "zh-CN", name: "Mandarin Chinese", native: "中文", flag: "🇨🇳", levels: "HSK", available: true),
        LanguageOption(id: "ko-KR", name: "Korean", native: "한국어", flag: "🇰🇷", levels: "Level", available: true),
        LanguageOption(id: "ja-JP", name: "Japanese", native: "日本語", flag: "🇯🇵", levels: "Level", available: true),
        LanguageOption(id: "es-ES", name: "Spanish", native: "Español", flag: "🇪🇸", levels: "CEFR", available: false),
        LanguageOption(id: "fr-FR", name: "French", native: "Français", flag: "🇫🇷", levels: "CEFR", available: false),
    ]

    /// The language the user picked (falls back to the first available one).
    static var current: LanguageOption {
        option(for: UserDefaults.standard.string(forKey: AppSettings.Key.language) ?? "")
    }

    /// The available language with this code, or the first available one.
    static func option(for code: String) -> LanguageOption {
        all.first { $0.id == code && $0.available } ?? all.first(where: \.available)!
    }

    /// "HSK 1", "Level 1".
    func levelName(_ level: Int) -> String {
        "\(levels) \(level)"
    }

    /// "HSK 1–3", or just "Level 1" while a language has one level.
    func levelRange(upTo top: Int) -> String {
        top <= 1 ? levelName(1) : "\(levels) 1–\(top)"
    }

    /// The Learn tab's browse option: "HSK levels" or "Levels".
    var levelsTitle: String {
        levels == "Level" ? "Levels" : "\(levels) levels"
    }
}

/// Cards for each language; available ones can be picked, the rest say "Coming soon".
struct LanguageList: View {
    @AppStorage(AppSettings.Key.language) private var selected = "zh-CN"

    var body: some View {
        VStack(spacing: 12) {
            ForEach(LanguageOption.all) { language in
                Button {
                    selected = language.id
                } label: {
                    row(language)
                }
                .buttonStyle(.plain)
                .disabled(!language.available)
            }
        }
    }

    private func row(_ language: LanguageOption) -> some View {
        let isSelected = language.available && selected == language.id
        return HStack(spacing: 14) {
            Text(language.flag)
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(Theme.chip, in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(language.name).font(.headline)
                Text(language.available ? "\(language.native) · \(detail(language))" : language.native)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if language.available {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.off)
            } else {
                Text("Coming soon")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.chip, in: .capsule)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
        }
        .contentShape(.rect)
        .accessibilityLabel(language.available ? language.name : "\(language.name), coming soon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "HSK 1–3 · 596 words"
    private func detail(_ language: LanguageOption) -> String {
        let library = AppContent.library(for: language.id)
        return "\(language.levelRange(upTo: library.hskLevels.last?.level ?? 1)) · \(library.words.count) words"
    }
}

/// The language list as its own screen, opened from the Learn header and Settings.
struct LanguagePickerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your progress in each language is kept, so you can switch back any time. Your alarm asks words in the language picked here.")
                        .foregroundStyle(Theme.muted)
                    LanguageList()
                }
                .padding(18)
            }
            .background(Theme.ground)
            .navigationTitle("Language")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
