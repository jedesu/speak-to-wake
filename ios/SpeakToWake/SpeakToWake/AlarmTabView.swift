import SwiftData
import SwiftUI

/// Alarm tab in the Soft Dawn style: a greeting, one card per alarm, and tips
/// only when they matter.
struct AlarmTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AlarmConfig.hour), SortDescriptor(\AlarmConfig.minute)])
    private var configs: [AlarmConfig]
    @Query private var reviews: [ReviewState]
    @Query private var progress: [PackProgress]

    private var controller = AlarmController.shared
    @State private var volume = VolumeMonitor()
    @State private var editing: AlarmConfig?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if controller.authorization == .denied {
                        tip("exclamationmark.triangle.fill", "Alarms are off for Mingo",
                            "Turn them on in Settings → Apps → Mingo.")
                    }
                    if volume.isLow && !configs.isEmpty {
                        tip("speaker.slash.fill", "Volume is at \(Int(volume.volume * 100))%",
                            "Turn it up so the challenge can wake you.")
                    }
                    if configs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "alarm").font(.system(size: 44)).foregroundStyle(Theme.accent)
                            Text("No alarms yet").font(.title3.bold())
                            Text("Tap + to set a wake-up alarm.").foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .card(padding: 32)
                    }
                    ForEach(configs) { config in
                        Button {
                            editing = config
                        } label: {
                            AlarmCard(config: config, words: AppSettings.promptsPerWake) { enabled in
                                config.enabled = enabled
                                Task { await controller.schedule(config) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if !configs.isEmpty {
                        wordsTip
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add alarm", systemImage: "plus") { adding = true }
                }
            }
            .settingsButton()
            .sheet(item: $editing) { config in
                AlarmEditView(config: config)
            }
            .sheet(isPresented: $adding) {
                AlarmEditView(config: nil)
            }
            .task {
                await controller.sync(configs)
            }
            .onAppear { volume.start() }
            .onDisappear { volume.stop() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.greeting(for: .now))
                .font(.subheadline.bold())
                .foregroundStyle(Theme.muted)
            Text("Your alarms")
                .font(.largeTitle.weight(.heavy))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    /// Which words tomorrow's alarm can ask.
    @ViewBuilder
    private var wordsTip: some View {
        let library = AppContent.library
        let learned = library.packs.filter { pack in progress.contains { $0.packID == pack.id && $0.learnedAt != nil } }
        if learned.isEmpty {
            tip("book.fill", "Learn your first words",
                "Your alarm asks words you've learned. Start with HSK 1 · Greetings in the Learn tab.")
        } else {
            tip("character.book.closed.fill", "Your alarm's words come from",
                "HSK 1 · " + learned.map(\.title).joined(separator: ", "))
        }
    }

    private func tip(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.link)
                .frame(width: 48, height: 48)
                .background(Theme.card, in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.heavy))
                Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.tip, in: .rect(cornerRadius: 24))
    }

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    static func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        if hours >= 24 {
            return "\(hours / 24) d \(hours % 24) h"
        }
        return hours > 0 ? "\(hours) h \(rest) min" : "\(rest) min"
    }
}

/// One alarm: big time, on/off switch, label, day circles, and when it rings next.
private struct AlarmCard: View {
    let config: AlarmConfig
    let words: Int
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(config.timeDigits)
                        .font(.system(size: 52, weight: .heavy))
                        .monospacedDigit()
                    if let period = config.amPM {
                        Text(period).font(.title3.bold()).foregroundStyle(config.enabled ? Theme.muted : Theme.off)
                    }
                }
                Spacer()
                Toggle("On", isOn: Binding(get: { config.enabled }, set: onToggle))
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            Text(config.label.isEmpty ? "Alarm" : config.label)
                .font(.headline)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let on = config.weekdays.contains(day)
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.caption.bold())
                        .frame(width: 30, height: 30)
                        .background(on && config.enabled ? Theme.accent : Theme.chip, in: .circle)
                        .foregroundStyle(on && config.enabled ? .white : Theme.muted)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(config.daysText)
            if config.enabled, let next = config.nextRingDate() {
                TimelineView(.everyMinute) { context in
                    Text("Rings in \(AlarmTabView.countdown(from: context.date, to: next)) · \(words) words to say")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .foregroundStyle(config.enabled ? Theme.text : Theme.off)
        .card(padding: 22)
    }
}

/// Add or edit an alarm, like the Clock app: time wheel, then Repeat and Label rows.
struct AlarmEditView: View {
    /// nil when adding a new alarm.
    let config: AlarmConfig?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var time = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? .now
    @State private var weekdays: Set<Int> = []
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink {
                        RepeatPicker(weekdays: $weekdays)
                    } label: {
                        LabeledContent("Repeat", value: AlarmConfig.daysText(for: weekdays, never: "Never"))
                    }
                    LabeledContent("Label") {
                        TextField("Alarm", text: $label)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let config {
                    Section {
                        Button("Delete Alarm", role: .destructive) {
                            AlarmController.shared.unschedule(config)
                            modelContext.delete(config)
                            try? modelContext.save()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(config == nil ? "Add Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: load)
            .softDawnList()
        }
    }

    private func load() {
        guard let config else { return }
        time = Calendar.current.date(from: DateComponents(hour: config.hour, minute: config.minute)) ?? time
        weekdays = Set(config.weekdays)
        label = config.label
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let target = config ?? AlarmConfig()
        target.hour = parts.hour ?? 7
        target.minute = parts.minute ?? 0
        target.weekdays = weekdays.sorted()
        target.label = label.trimmingCharacters(in: .whitespaces)
        target.enabled = true
        if config == nil { modelContext.insert(target) }
        try? modelContext.save()
        Task { await AlarmController.shared.schedule(target) }
        dismiss()
    }
}

/// "Every Monday" ... "Every Sunday" with checkmarks, like the Clock app.
private struct RepeatPicker: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        List {
            ForEach(1...7, id: \.self) { day in
                Button {
                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    HStack {
                        Text("Every \(Calendar.current.weekdaySymbols[day - 1])")
                            .foregroundStyle(.primary)
                        Spacer()
                        if weekdays.contains(day) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Repeat")
    }
}
