import SwiftUI
import SleepCoachAnalysis

struct TonightView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                SleepTheme.background.ignoresSafeArea()
                if let night = model.lastNight, let analysis = model.lastAnalysis {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header(night)
                            HStack {
                                Spacer()
                                ScoreRingView(score: analysis.score.total)
                                Spacer()
                            }
                            metrics(night)
                            SleepCard { HypnogramView(night: night) }
                            componentScores(analysis.score)
                            insights(analysis.insights)
                            FlaggedEventsView(events: analysis.flaggedEvents)
                            Text(SafetyCopy.shortDisclaimer)
                                .font(.caption)
                                .foregroundStyle(SleepTheme.muted)
                                .padding(.bottom, 24)
                        }
                        .padding(.horizontal, 18)
                    }
                    .refreshable { await model.refresh() }
                } else {
                    empty
                }
            }
            .navigationTitle("Last night")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.useSampleData {
                        Text("Sample")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(SleepTheme.accent.opacity(0.2)))
                            .foregroundStyle(SleepTheme.accent)
                    }
                }
            }
        }
    }

    private func header(_ night: SleepNight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(night.morningDate, format: .dateTime.weekday(.wide).month().day())
                .font(.title3.weight(.semibold))
                .foregroundStyle(SleepTheme.cream)
            Text("On-device score from duration, consistency, stages, restlessness and overnight heart trends.")
                .font(.caption)
                .foregroundStyle(SleepTheme.muted)
        }
    }

    private func metrics(_ night: SleepNight) -> some View {
        HStack(spacing: 10) {
            metric("Asleep", InsightGenerator.hoursMinutes(night.asleepDuration))
            metric("In bed", InsightGenerator.hoursMinutes(night.inBedDuration))
            metric("Efficiency", "\(Int((night.sleepEfficiency * 100).rounded()))%")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        SleepCard {
            Text(title).font(.caption).foregroundStyle(SleepTheme.muted)
            Text(value).font(.headline).foregroundStyle(SleepTheme.cream)
        }
    }

    private func componentScores(_ score: SleepScore) -> some View {
        SleepCard {
            Text("Score mix").font(.headline).foregroundStyle(SleepTheme.cream)
            ForEach(Array([
                ("Duration", score.duration),
                ("Consistency", score.consistency),
                ("Stages", score.stages),
                ("Restlessness", score.restlessness),
                ("Recovery", score.recovery)
            ]), id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.0).font(.caption).foregroundStyle(SleepTheme.muted)
                        Spacer()
                        Text("\(Int(item.1.rounded()))").font(.caption.monospacedDigit()).foregroundStyle(SleepTheme.cream)
                    }
                    GeometryReader { geo in
                        Capsule().fill(SleepTheme.cardStroke)
                        Capsule()
                            .fill(SleepTheme.accent)
                            .frame(width: geo.size.width * CGFloat(item.1 / 100))
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    private func insights(_ items: [Insight]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insights").font(.headline).foregroundStyle(SleepTheme.cream)
            ForEach(items) { insight in
                SleepCard {
                    Text(insight.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(insight.category == .breathing ? SleepTheme.warning : SleepTheme.cream)
                    Text(insight.body)
                        .font(.footnote)
                        .foregroundStyle(SleepTheme.muted)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.largeTitle)
                .foregroundStyle(SleepTheme.accent)
            Text("No night on file yet")
                .foregroundStyle(SleepTheme.cream)
            Text("Wear Apple Watch to bed, or keep sample data on in Settings to preview the UI.")
                .font(.footnote)
                .foregroundStyle(SleepTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    TonightView()
        .environment(AppModel.preview)
}
