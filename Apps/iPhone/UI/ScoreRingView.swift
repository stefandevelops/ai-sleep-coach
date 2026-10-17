import SwiftUI

struct ScoreRingView: View {
    var score: Int
    var size: CGFloat = 168

    var body: some View {
        ZStack {
            Circle()
                .stroke(SleepTheme.cardStroke, lineWidth: 14)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    SleepTheme.scoreColor(score),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(SleepTheme.cream)
                Text("Sleep quality")
                    .font(.caption)
                    .foregroundStyle(SleepTheme.muted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Sleep quality score \(score) out of 100")
    }
}

#Preview {
    ScoreRingView(score: 86)
        .padding()
        .background(SleepTheme.background)
}
