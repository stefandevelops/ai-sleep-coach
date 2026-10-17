import Foundation

public struct InsightGenerator: InsightGenerating {
    public init() {}

    public func insights(
        night: SleepNight,
        history: [SleepNight],
        score: SleepScore,
        events: [FlaggedEvent]
    ) -> [Insight] {
        var items: [Insight] = []
        items.append(durationInsight(night: night, score: score))
        items.append(consistencyInsight(night: night, history: history, score: score))
        items.append(stagesInsight(night: night, score: score))
        items.append(restlessnessInsight(night: night, score: score))
        items.append(recoveryInsight(night: night, history: history, score: score))
        if let breathing = breathingInsight(night: night, events: events) {
            items.append(breathing)
        }
        if night.isSampleData {
            items.append(
                Insight(
                    title: "Sample data is on",
                    body: "This night is simulated so you can browse the app without a Watch. Turn sample data off in Settings when HealthKit is authorised.",
                    category: .dataQuality
                )
            )
        } else if night.provenance.sleepStagesSource == .appleWatch {
            items.append(
                Insight(
                    title: "Stages from Apple Watch",
                    body: "Sleep stages came from Apple’s own sleep analysis. AI Sleep Coach did not write a second copy of those stages into Health.",
                    category: .appleHealth
                )
            )
        }
        return items.filter { !SafetyCopy.containsBannedDiagnosisLanguage($0.title + " " + $0.body) }
    }

    private func durationInsight(night: SleepNight, score: SleepScore) -> Insight {
        let hours = night.asleepDuration / 3600
        let formatted = Self.hoursMinutes(night.asleepDuration)
        if score.duration >= 85 {
            return Insight(
                title: "Time asleep looked solid",
                body: "About \(formatted) asleep, which sits in a commonly recommended 7–9 hour window. That’s a duration score, not a health claim.",
                category: .duration
            )
        }
        if hours < 7 {
            return Insight(
                title: "Shorter night than the usual target",
                body: "About \(formatted) asleep. Many adults aim nearer 7–9 hours; a short night often pulls the score down. One night is not a pattern.",
                category: .duration
            )
        }
        return Insight(
            title: "A long stretch in bed",
            body: "About \(formatted) asleep, which is longer than the 7–9 hour target used in the score. Long nights can be restful or a sign you needed catch-up sleep.",
            category: .duration
        )
    }

    private func consistencyInsight(night: SleepNight, history: [SleepNight], score: SleepScore) -> Insight {
        if history.count < 2 {
            return Insight(
                title: "Consistency needs a few more nights",
                body: "Bedtime regularity is scored once several mornings are on file. Keep using the app overnight to see the trend.",
                category: .consistency
            )
        }
        if score.consistency >= 80 {
            return Insight(
                title: "Bedtime has been fairly steady",
                body: "Recent nights clustered around a similar lights-out time, which often feels easier than a shifting schedule.",
                category: .consistency
            )
        }
        return Insight(
            title: "Bedtimes have been scattered",
            body: "Lights-out jumped around across recent nights. A more regular window is one of the simpler levers the score watches.",
            category: .consistency
        )
    }

    private func stagesInsight(night: SleepNight, score: SleepScore) -> Insight {
        guard night.hasDetailedStages else {
            return Insight(
                title: "Stages were not detailed",
                body: "Apple Watch did not provide Core/Deep/REM breakdown for this night, so the stage component stays conservative. Wear the Watch to bed with Sleep tracking on.",
                category: .stages
            )
        }
        let asleep = max(night.asleepDuration, 1)
        let deep = Int((night.duration(for: .deep) / asleep * 100).rounded())
        let rem = Int((night.duration(for: .rem) / asleep * 100).rounded())
        if score.stages >= 80 {
            return Insight(
                title: "Stage mix looked balanced",
                body: "Roughly \(deep)% deep and \(rem)% REM of time asleep. Those percentages are descriptive, not a clinical reading.",
                category: .stages
            )
        }
        return Insight(
            title: "Stage mix was a bit lopsided",
            body: "About \(deep)% deep and \(rem)% REM of time asleep. Alcohol, late exercise or a short night often show up here. Not a diagnosis.",
            category: .stages
        )
    }

    private func restlessnessInsight(night: SleepNight, score: SleepScore) -> Insight {
        let waso = Int((night.waso / 60).rounded())
        if score.restlessness >= 80 {
            return Insight(
                title: "Overnight movement stayed low",
                body: "About \(waso) minutes awake after falling asleep, with a quiet wrist-motion trace. Restlessness scoring uses motion plus those wake bouts.",
                category: .restlessness
            )
        }
        return Insight(
            title: "A more restless night",
            body: "About \(waso) minutes awake after sleep onset and/or more wrist motion. Heat, pets, late caffeine or breathing-related arousals can all contribute.",
            category: .restlessness
        )
    }

    private func recoveryInsight(night: SleepNight, history: [SleepNight], score: SleepScore) -> Insight {
        if night.heartRateBPM.isEmpty && night.hrvSDNN.isEmpty {
            return Insight(
                title: "Heart data was thin",
                body: "Not enough heart rate or HRV samples to judge overnight recovery, so that component stayed neutral.",
                category: .recovery
            )
        }
        let hr = Statistics.mean(night.heartRateBPM.map(\.value)).map { Int($0.rounded()) }
        if score.recovery >= 80 {
            return Insight(
                title: "Heart rate settled overnight",
                body: hr.map { "Average heart rate around \($0) bpm, with HRV in a comfortable range versus recent nights." }
                    ?? "HRV and overnight heart rate looked settled versus recent nights.",
                category: .recovery
            )
        }
        return Insight(
            title: "Overnight heart signals were busier",
            body: "Heart rate and/or HRV looked less settled than a typical recovery night. Illness, alcohol, heat or a hard training day are common reasons.",
            category: .recovery
        )
    }

    private func breathingInsight(night: SleepNight, events: [FlaggedEvent]) -> Insight? {
        let appEvents = events.filter { $0.kind != .appleElevatedBreathingDisturbances }
        if events.contains(where: { $0.kind == .appleElevatedBreathingDisturbances }) {
            return Insight(
                title: SafetyCopy.breathingFlagTitle,
                body: SafetyCopy.appleElevatedAdvice,
                category: .breathing
            )
        }
        guard !appEvents.isEmpty else { return nil }
        let hours = max(night.asleepDuration / 3600, 0.25)
        let perHour = Double(appEvents.count) / hours
        return Insight(
            title: SafetyCopy.breathingFlagTitle,
            body: "The on-device heuristic flagged \(appEvents.count) possible events (about \(String(format: "%.1f", perHour)) per hour of sleep) from oxygen dips, respiratory-rate irregularity and/or heart-rate swings. \(SafetyCopy.breathingFlagAdvice)",
            category: .breathing
        )
    }

    public static func hoursMinutes(_ interval: TimeInterval) -> String {
        let total = Int((interval / 60).rounded())
        let h = total / 60
        let m = total % 60
        return "\(h)h \(m)m"
    }
}
