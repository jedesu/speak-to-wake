import SwiftUI

/// A language Mingo teaches, or will. Only Mandarin has words so far; the others
/// show as "Coming soon" so the picker reflects the plan.
struct LanguageOption: Identifiable, Hashable {
    let id: String          // locale code, matches the word data files (words.<id>.json)
    let name: String
    let native: String
    let flag: String
    /// The level system its sections follow, e.g. "HSK".
    let levels: String
    let available: Bool

    static let all: [LanguageOption] = [
        LanguageOption(id: "zh-CN", name: "Mandarin Chinese", native: "中文", flag: "🇨🇳", levels: "HSK", available: true),
        LanguageOption(id: "ja-JP", name: "Japanese", native: "日本語", flag: "🇯🇵", levels: "JLPT", available: false),
        LanguageOption(id: "ko-KR", name: "Korean", native: "한국어", flag: "🇰🇷", levels: "TOPIK", available: false),
        LanguageOption(id: "es-ES", name: "Spanish", native: "Español", flag: "🇪🇸", levels: "CEFR", available: false),
        LanguageOption(id: "fr-FR", name: "French", native: "Français", flag: "🇫🇷", levels: "CEFR", available: false),
    ]

    /// The language the user picked (falls back to the first available one).
    static var current: LanguageOption {
        let code = UserDefaults.standard.string(forKey: AppSettings.Key.language)
        return all.first { $0.id == code && $0.available } ?? all.first(where: \.available)!
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
                Text(language.native).font(.subheadline).foregroundStyle(Theme.muted)
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
}

/// The language list as its own screen, opened from the Learn header and Settings.
struct LanguagePickerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mingo works with any language you're learning. Mandarin is ready now; more are on the way.")
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
