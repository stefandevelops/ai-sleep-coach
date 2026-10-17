import SwiftUI
import SleepCoachAnalysis

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        TabView {
            sessionPage
            scorePage
        }
        .tabViewStyle(.verticalPage)
        .background(Color.black)
    }

    private var sessionPage: some View {
        VStack(spacing: 10) {
            Text(model.isRunning ? "Sleep session" : "AI Sleep Coach")
                .font(.headline)
            if model.isRunning, let started = model.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsed(from: started, now: context.date))
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                        .foregroundStyle(.cyan)
                }
                Text("Wrist motion recording")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(model.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(model.isRunning ? "End sleep" : "Start sleep") {
                model.toggle()
            }
            .tint(model.isRunning ? .orange : Color(red: 0.55, green: 0.62, blue: 1.0))
        }
        .padding()
    }

    private var scorePage: some View {
        VStack(spacing: 8) {
            Text("Last night")
                .font(.headline)
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(model.lastScore ?? 0) / 100)
                    .stroke(Color(red: 0.49, green: 0.81, blue: 0.63), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(model.lastScore ?? 0)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
            }
            .frame(width: 96, height: 96)
            Text(SafetyCopy.shortDisclaimer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func elapsed(from start: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }
}

#Preview {
    WatchRootView()
        .environment(WatchModel())
}
