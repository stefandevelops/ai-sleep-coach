import Foundation

/// Payload the Watch sends after an overnight session so the iPhone can merge
/// wrist-motion with HealthKit vitals. Lives in the portable package so both
/// targets share one Codable contract.
public struct SleepSessionDraft: Codable, Sendable, Equatable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var motion: [MotionSample]
    public var watchHeartRateBPM: [TimedSample]
    public var notes: String?

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        motion: [MotionSample],
        watchHeartRateBPM: [TimedSample] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.motion = motion
        self.watchHeartRateBPM = watchHeartRateBPM
        self.notes = notes
    }

    public func asCoachNight(morning: Date) -> SleepNight {
        let inferred = inferredStages()
        return SleepNight(
            id: id,
            morningDate: morning,
            inBedStart: start,
            inBedEnd: end,
            stages: inferred,
            heartRateBPM: watchHeartRateBPM,
            motion: motion,
            provenance: NightProvenance(
                sleepStagesSource: .aiSleepCoachSession,
                vitalsSource: watchHeartRateBPM.isEmpty ? .unknown : .aiSleepCoachSession,
                motionSource: .aiSleepCoachSession
            ),
            isSampleData: false
        )
    }

    /// Very conservative motion-based awake vs asleep. Replaced by Apple stages
    /// whenever they exist for the same night.
    public func inferredStages() -> [SleepStageInterval] {
        guard !motion.isEmpty else {
            return [
                SleepStageInterval(
                    start: start,
                    end: end,
                    stage: .asleepUnspecified,
                    source: .aiSleepCoachSession
                )
            ]
        }
        var intervals: [SleepStageInterval] = []
        var currentStage: SleepStage = motion[0].magnitude >= 0.05 ? .awake : .asleepUnspecified
        var currentStart = motion[0].date
        for sample in motion.dropFirst() {
            let stage: SleepStage = sample.magnitude >= 0.05 ? .awake : .asleepUnspecified
            if stage != currentStage {
                intervals.append(
                    SleepStageInterval(
                        start: currentStart,
                        end: sample.date,
                        stage: currentStage,
                        source: .aiSleepCoachSession
                    )
                )
                currentStage = stage
                currentStart = sample.date
            }
        }
        intervals.append(
            SleepStageInterval(
                start: currentStart,
                end: end,
                stage: currentStage,
                source: .aiSleepCoachSession
            )
        )
        return intervals
    }
}
