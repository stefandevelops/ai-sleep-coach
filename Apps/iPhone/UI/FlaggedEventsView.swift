import SwiftUI
import SleepCoachAnalysis

struct FlaggedEventsView: View {
    var events: [FlaggedEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flagged events")
                .font(.headline)
                .foregroundStyle(SleepTheme.cream)
            if events.isEmpty {
                SleepCard {
                    Text("Nothing unusual was flagged")
                        .foregroundStyle(SleepTheme.cream)
                    Text("The heuristic looks for SpO₂ dips, irregular respiratory rate and heart-rate swings. Absence of flags is not medical clearance.")
                        .font(.footnote)
                        .foregroundStyle(SleepTheme.muted)
                }
            } else {
                ForEach(events) { event in
                    SleepCard {
                        HStack {
                            Text(title(event.kind))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SleepTheme.warning)
                            Spacer()
                            Text(event.timestamp, format: .dateTime.hour().minute())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(SleepTheme.muted)
                        }
                        Text("\(Int(event.duration.rounded()))s · \(event.severity.rawValue)")
                            .font(.caption)
                            .foregroundStyle(SleepTheme.accent)
                        Text(event.explanation)
                            .font(.footnote)
                            .foregroundStyle(SleepTheme.muted)
                    }
                }
            }
        }
    }

    private func title(_ kind: FlaggedEventKind) -> String {
        switch kind {
        case .possibleSpO2Dip: return "Possible SpO₂ dip"
        case .respiratoryIrregularity: return "Respiratory irregularity"
        case .heartRatePattern: return "Heart-rate swing"
        case .combinedBreathingPattern: return SafetyCopy.breathingFlagTitle
        case .appleElevatedBreathingDisturbances: return "Apple: elevated BD"
        }
    }
}

#Preview {
    FlaggedEventsView(events: [])
        .padding()
        .background(SleepTheme.background)
}
