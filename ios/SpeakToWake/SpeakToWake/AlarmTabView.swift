import SwiftData
import SwiftUI

/// Alarm tab, laid out like the Clock app's Alarms list.
struct AlarmTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AlarmConfig.hour), SortDescriptor(\AlarmConfig.minute)])
    private var configs: [AlarmConfig]
    @Query private var reviews: [ReviewState]

    private var controller = AlarmController.shared
    @State private var volume = VolumeMonitor()
    @State private var editing: AlarmConfig?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                notices
                ForEach(configs) { config in
                    AlarmRow(config: config) { enabled in
                        config.enabled = enabled
                        Task { await controller.schedule(config) }
                    }
                    .contentShape(.rect)
                    .onTapGesture { editing = config }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .overlay {
                if configs.isEmpty {
                    ContentUnavailableView {
                        Label("No Alarms", systemImage: "alarm")
                    } description: {
                        Text("Tap + to set a wake-up alarm.")
                    }
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !configs.isEmpty { EditButton() }
                }
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

    /// Small notes above the list, only when they matter.
    @ViewBuilder
    private var notices: some View {
        if let next = configs.filter(\.enabled).compactMap({ $0.nextRingDate() }).min() {
            TimelineView(.everyMinute) { context in
                Text("Next alarm in \(Self.countdown(from: context.date, to: next))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
        }
        if controller.authorization == .denied {
            notice("Alarms are off for Mingo. Turn them on in Settings → Apps → Mingo.",
                   systemImage: "exclamationmark.triangle.fill", color: .red)
        }
        if volume.isLow && !configs.isEmpty {
            notice("Volume is at \(Int(volume.volume * 100))%. Turn it up so the challenge can wake you.",
                   systemImage: "speaker.slash.fill", color: .orange)
        }
        if reviews.isEmpty && !configs.isEmpty {
            notice("Your alarm asks words you've learned. Learn your first section in the Learn tab.",
                   systemImage: "book.fill", color: .blue)
        }
    }

    private func notice(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(color)
            .listRowSeparator(.hidden)
    }

    static func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        if hours >= 24 {
            return "\(hours / 24) d \(hours % 24) h"
        }
        return hours > 0 ? "\(hours) h \(rest) min" : "\(rest) min"
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            controller.unschedule(configs[index])
            modelContext.delete(configs[index])
        }
        try? modelContext.save()
    }
}

private struct AlarmRow: View {
    let config: AlarmConfig
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(config.timeDigits)
                        .font(.system(size: 58, weight: .light))
                        .monospacedDigit()
                    if let period = config.amPM {
                        Text(period)
                            .font(.system(size: 28, weight: .light))
                    }
                }
                Text(config.subtitle)
                    .font(.subheadline)
            }
            .foregroundStyle(config.enabled ? .primary : .secondary)
            Spacer()
            Toggle("On", isOn: Binding(get: { config.enabled }, set: onToggle))
                .labelsHidden()
                .tint(.green)
        }
        .padding(.vertical, 2)
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
