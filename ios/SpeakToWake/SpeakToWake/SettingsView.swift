import SwiftUI

/// Settings, opened from the gear icon on every tab. Real settings come in piece 7.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Developer") {
                    NavigationLink("Speech check") { SpeechCheckView() }
                    NavigationLink("Alarm test") { AlarmTestView() }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SettingsButton: ViewModifier {
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

extension View {
    /// Adds the gear icon that opens Settings.
    func settingsButton() -> some View {
        modifier(SettingsButton())
    }
}
