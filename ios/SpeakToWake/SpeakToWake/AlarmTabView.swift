import SwiftData
import SwiftUI

/// Alarm tab: the user's alarms, like the Clock app, plus a volume check.
struct AlarmTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AlarmConfig.hour), SortDescriptor(\AlarmConfig.minute)])
    private var configs: [AlarmConfig]
    @Query private var reviews: [ReviewState]

    private var controller = AlarmController.shared
    @State private var editing: AlarmConfig?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    nextRingRow
                    VolumeCheckView()
                }
                if controller.authorization == .denied {
                    Section {
                        Label("Alarms are turned off for Mingo. Turn them on in Settings → Apps → Mingo.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if reviews.isEmpty {
                    Section {
                        Label("Your alarm only asks words you've learned. Learn a pack first in the Learn tab.",
                              systemImage: "book")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if configs.isEmpty {
                        Text("No alarms yet. Tap + to add one.").foregroundStyle(.secondary)
                    }
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
            }
            .navigationTitle("Alarm")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
        }
    }

    @ViewBuilder
    private var nextRingRow: some View {
        let next = configs.filter(\.enabled).compactMap { $0.nextRingDate() }.min()
        TimelineView(.everyMinute) { context in
            if let next {
                Label("Rings in \(Self.countdown(from: context.date, to: next))", systemImage: "alarm.fill")
                    .font(.headline)
            } else {
                Label("No alarm set", systemImage: "alarm")
                    .foregroundStyle(.secondary)
            }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(config.timeText)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text([config.label, config.daysText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(config.enabled ? .primary : .secondary)
            Spacer()
            Toggle("On", isOn: Binding(get: { config.enabled }, set: onToggle))
                .labelsHidden()
        }
    }
}

/// Add or edit an alarm: time wheel, repeat days, label.
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
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                Section("Repeat") {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            let on = weekdays.contains(day)
                            Button {
                                if on { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                    .font(.headline)
                                    .frame(width: 38, height: 38)
                                    .background(on ? Color.orange : Color.secondary.opacity(0.15), in: .circle)
                                    .foregroundStyle(on ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    HStack {
                        Button("Weekdays") { weekdays = [2, 3, 4, 5, 6] }
                        Spacer()
                        Button("Every day") { weekdays = Set(1...7) }
                        Spacer()
                        Button("Once") { weekdays = [] }
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }

                Section("Label") {
                    TextField("Wake up early", text: $label)
                }

                if let config {
                    Section {
                        Button("Delete alarm", role: .destructive) {
                            AlarmController.shared.unschedule(config)
                            modelContext.delete(config)
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(config == nil ? "Add alarm" : "Edit alarm")
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
