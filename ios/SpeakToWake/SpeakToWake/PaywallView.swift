import SwiftUI

/// Mingo Pro offer with a 7-day free trial. Payments aren't built yet, so starting
/// the trial unlocks Pro on this phone (a fake door: it shows what people choose).
struct PaywallView: View {
    let onDone: () -> Void

    private enum Plan { case yearly, monthly }
    @State private var plan = Plan.yearly

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MINGO PRO")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accent)
                    Text("Try Pro free for 7 days")
                        .font(.largeTitle.weight(.heavy))
                    Text("Your alarm picks the words you're about to forget, so every morning counts.")
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feature("brain.head.profile", "Spaced repetition", "The alarm and Review bring back words right before you'd forget them")
                    feature("square.stack.3d.up.fill", "Every word pack", "All HSK levels and topics, not just the starter sections")
                    feature("chart.bar.fill", "Detailed progress", "See which words stick and which keep slipping")
                    feature("globe", "New languages as they launch", "Japanese and Korean are next")
                }
                .card(padding: 20)

                timeline

                VStack(spacing: 10) {
                    planRow(.yearly, title: "Yearly", price: "$49.99 / year", detail: "$4.17 a month", badge: "Save 17%")
                    planRow(.monthly, title: "Monthly", price: "$4.99 / month", detail: "Cancel anytime", badge: nil)
                }

                Button("Start my free week") {
                    UserDefaults.standard.set(true, forKey: AppSettings.Key.proUnlocked)
                    UserDefaults.standard.set(Date.now, forKey: "trialStartedAt")
                    UserDefaults.standard.set(plan == .yearly ? "yearly" : "monthly", forKey: "trialPlan")
                    onDone()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Continue with free") { onDone() }
                    .font(.headline)
                    .foregroundStyle(Theme.link)
                    .frame(maxWidth: .infinity, minHeight: 44)

                Text("Free keeps the speaking alarm, every challenge type and the starter sections. We'll remind you 2 days before the trial ends, and you can cancel in one tap. Payments aren't live in this test version, so no card is needed.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(Theme.ground)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.chip, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
    }

    /// Today → reminder → first charge, so nobody is surprised.
    private var timeline: some View {
        HStack(alignment: .top, spacing: 0) {
            stop("Today", "Full access", filled: true)
            stop("Day 5", "Reminder", filled: false)
            stop("Day 7", plan == .yearly ? "$49.99" : "$4.99", filled: false)
        }
        .background(alignment: .top) {
            Rectangle().fill(Theme.toggleOff).frame(height: 2).padding(.horizontal, 50).padding(.top, 9)
        }
    }

    private func stop(_ day: String, _ detail: String, filled: Bool) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(filled ? Theme.accent : Theme.card)
                .stroke(Theme.accent, lineWidth: 2)
                .frame(width: 20, height: 20)
            Text(day).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func planRow(_ option: Plan, title: String, price: String, detail: String, badge: String?) -> some View {
        let selected = plan == option
        return Button {
            plan = option
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Theme.accent : Theme.off)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent, in: .capsule)
                        }
                    }
                    Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(price).font(.subheadline.bold())
            }
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Theme.accent : Theme.toggleOff, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
