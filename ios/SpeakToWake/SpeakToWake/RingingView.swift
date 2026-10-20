import SwiftUI

/// The full-screen "alarm is ringing" page shown before the challenge, like
/// Alarmy's: big clock, the alarm's label, a bouncing mascot and one Start button.
struct RingingView: View {
    var label: String?
    let onStart: () -> Void

    @State private var bounce = false

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 2) {
                    Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.title3.bold())
                        .foregroundStyle(Theme.muted)
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 84, weight: .heavy))
                        .monospacedDigit()
                }
            }
            .padding(.top, 48)

            Text(label ?? "Time to wake up")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Theme.chip, in: .capsule)

            Spacer()
            Text("🐼")
                .font(.system(size: 150))
                .scaleEffect(bounce ? 1.06 : 0.95)
                .offset(y: bounce ? -14 : 6)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: bounce)
                .onAppear { bounce = true }
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("早上好！").font(.system(size: 34, weight: .bold))
                Text("Good morning. Ready for your words?")
                    .foregroundStyle(Theme.muted)
            }
            Spacer()

            Button("Start", action: onStart)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.ground)
    }
}

#Preview {
    RingingView {}
}
