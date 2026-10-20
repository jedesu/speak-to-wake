import SwiftUI

/// The full-screen "alarm is ringing" page shown before the challenge, like
/// Alarmy's: big clock, a label, a bouncing mascot and one big Start button.
struct RingingView: View {
    var label: String?
    let onStart: () -> Void

    @State private var bounce = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 4) {
                        Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.title3.weight(.semibold))
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 88, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.white)
                .padding(.top, 40)

                Text("☀️ \(label ?? "Time to wake up")")
                    .font(.title3.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.25), in: .capsule)
                    .foregroundStyle(.white)

                Spacer()
                Text("🐼")
                    .font(.system(size: 160))
                    .scaleEffect(bounce ? 1.08 : 0.94)
                    .rotationEffect(.degrees(bounce ? 6 : -6))
                    .offset(y: bounce ? -16 : 8)
                    .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: bounce)
                    .onAppear { bounce = true }
                    .accessibilityHidden(true)
                Text("早上好!  zǎoshang hǎo")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()

                Button(action: onStart) {
                    Text("Start")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .clipShape(.capsule)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

#Preview {
    RingingView {}
}
