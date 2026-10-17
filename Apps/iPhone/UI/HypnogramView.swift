import SwiftUI
import SleepCoachAnalysis

struct HypnogramView: View {
    var night: SleepNight

    private var rows: [(SleepStage, String)] {
        [(.awake, "Awake"), (.rem, "REM"), (.core, "Core"), (.deep, "Deep")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hypnogram")
                .font(.headline)
                .foregroundStyle(SleepTheme.cream)
            GeometryReader { geo in
                let width = geo.size.width
                let span = max(night.inBedDuration, 1)
                ZStack(alignment: .leading) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        Rectangle()
                            .fill(SleepTheme.color(for: row.0).opacity(0.08))
                            .frame(height: geo.size.height / 4)
                            .offset(y: CGFloat(index) * geo.size.height / 4)
                    }
                    ForEach(night.stages) { interval in
                        let x = CGFloat(interval.start.timeIntervalSince(night.inBedStart) / span) * width
                        let w = max(2, CGFloat(interval.duration / span) * width)
                        let row = rowIndex(interval.stage)
                        Capsule()
                            .fill(SleepTheme.color(for: displayStage(interval.stage)))
                            .frame(width: w, height: geo.size.height / 4 - 8)
                            .offset(
                                x: x,
                                y: CGFloat(row) * geo.size.height / 4 + 4
                            )
                    }
                }
            }
            .frame(height: 132)
            HStack {
                ForEach(rows, id: \.1) { row in
                    HStack(spacing: 6) {
                        Circle().fill(SleepTheme.color(for: row.0)).frame(width: 8, height: 8)
                        Text(row.1).font(.caption2).foregroundStyle(SleepTheme.muted)
                    }
                }
                Spacer()
            }
            HStack {
                Text(night.inBedStart, format: .dateTime.hour().minute())
                Spacer()
                Text(night.inBedEnd, format: .dateTime.hour().minute())
            }
            .font(.caption2)
            .foregroundStyle(SleepTheme.muted)
        }
    }

    private func displayStage(_ stage: SleepStage) -> SleepStage {
        stage == .asleepUnspecified ? .core : stage
    }

    private func rowIndex(_ stage: SleepStage) -> Int {
        switch stage {
        case .awake, .inBed: return 0
        case .rem: return 1
        case .core, .asleepUnspecified: return 2
        case .deep: return 3
        }
    }
}

#Preview {
    HypnogramView(night: SampleDataFactory.perfectNight(morning: .now))
        .padding()
        .background(SleepTheme.background)
}
