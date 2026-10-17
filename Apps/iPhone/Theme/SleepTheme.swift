import SwiftUI
import SleepCoachAnalysis

enum SleepTheme {
    static let background = Color(red: 0.03, green: 0.04, blue: 0.09)
    static let card = Color(red: 0.07, green: 0.09, blue: 0.17)
    static let cardStroke = Color.white.opacity(0.06)
    static let accent = Color(red: 0.55, green: 0.62, blue: 1.0)
    static let cream = Color(red: 0.93, green: 0.93, blue: 0.90)
    static let muted = Color.white.opacity(0.58)
    static let warning = Color(red: 0.91, green: 0.66, blue: 0.49)
    static let good = Color(red: 0.49, green: 0.81, blue: 0.63)

    static func color(for stage: SleepCoachAnalysis.SleepStage) -> Color {
        switch stage {
        case .awake: return Color(red: 0.91, green: 0.75, blue: 0.48)
        case .rem: return Color(red: 0.79, green: 0.63, blue: 1.0)
        case .core: return Color(red: 0.42, green: 0.54, blue: 1.0)
        case .deep: return Color(red: 0.24, green: 0.29, blue: 0.62)
        case .asleepUnspecified: return accent
        case .inBed: return Color.white.opacity(0.18)
        }
    }

    static func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return good }
        if score >= 60 { return accent }
        return warning
    }
}

struct SleepCard<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(SleepTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(SleepTheme.cardStroke, lineWidth: 1)
                )
        )
    }
}
