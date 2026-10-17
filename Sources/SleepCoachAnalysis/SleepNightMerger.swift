import Foundation

/// Prefers Apple Watch sleep stages when they already cover the night so the
/// app does not manufacture a second HealthKit sleep timeline.
public struct SleepNightMerger: Sendable {
    public var minimumAppleAsleepHours: Double

    public init(minimumAppleAsleepHours: Double = 2.0) {
        self.minimumAppleAsleepHours = minimumAppleAsleepHours
    }

    public func appleStagesAreAuthoritative(_ apple: SleepNight?) -> Bool {
        guard let apple else { return false }
        return apple.asleepDuration >= minimumAppleAsleepHours * 3600
    }

    public func shouldWriteCoachSleepAnalysis(
        apple: SleepNight?,
        coach: SleepNight?
    ) -> Bool {
        guard coach != nil else { return false }
        return !appleStagesAreAuthoritative(apple)
    }

    public func merge(apple: SleepNight?, coach: SleepNight?) -> SleepNight? {
        switch (apple, coach) {
        case let (apple?, nil):
            return apple
        case let (nil, coach?):
            return coach
        case let (apple?, coach?):
            return combine(apple: apple, coach: coach)
        case (nil, nil):
            return nil
        }
    }

    private func combine(apple: SleepNight, coach: SleepNight) -> SleepNight {
        let useAppleStages = appleStagesAreAuthoritative(apple)
        let stages = useAppleStages ? apple.stages : (coach.stages.isEmpty ? apple.stages : coach.stages)
        let inBedStart = min(apple.inBedStart, coach.inBedStart)
        let inBedEnd = max(apple.inBedEnd, coach.inBedEnd)
        return SleepNight(
            id: apple.id,
            morningDate: apple.morningDate,
            inBedStart: useAppleStages ? apple.inBedStart : inBedStart,
            inBedEnd: useAppleStages ? apple.inBedEnd : inBedEnd,
            stages: stages,
            heartRateBPM: preferNonEmpty(apple.heartRateBPM, coach.heartRateBPM),
            hrvSDNN: preferNonEmpty(apple.hrvSDNN, coach.hrvSDNN),
            spo2Percent: preferNonEmpty(apple.spo2Percent, coach.spo2Percent),
            respiratoryRateBPM: preferNonEmpty(apple.respiratoryRateBPM, coach.respiratoryRateBPM),
            wristTemperatureDeltaC: apple.wristTemperatureDeltaC ?? coach.wristTemperatureDeltaC,
            motion: coach.motion.isEmpty ? apple.motion : coach.motion,
            appleBreathingDisturbances: apple.appleBreathingDisturbances ?? coach.appleBreathingDisturbances,
            provenance: NightProvenance(
                sleepStagesSource: useAppleStages ? .appleWatch : .merged,
                vitalsSource: apple.heartRateBPM.isEmpty ? .aiSleepCoachSession : .merged,
                motionSource: coach.motion.isEmpty ? apple.provenance.motionSource : .aiSleepCoachSession
            ),
            isSampleData: apple.isSampleData && coach.isSampleData
        )
    }

    private func preferNonEmpty(_ apple: [TimedSample], _ coach: [TimedSample]) -> [TimedSample] {
        if apple.isEmpty { return coach }
        if coach.isEmpty { return apple }
        return apple
    }
}
