import Foundation

public struct ScoringConfiguration: Codable, Sendable, Equatable {
    public var weights: ScoreWeights
    public var targetSleepHours: ClosedRange<Double>
    public var durationShortPenaltyPerHour: Double
    public var durationLongPenaltyPerHour: Double
    public var restlessnessMotionThresholdG: Double

    public static let `default` = ScoringConfiguration(
        weights: .default,
        targetSleepHours: 7.0...9.0,
        durationShortPenaltyPerHour: 35,
        durationLongPenaltyPerHour: 18,
        restlessnessMotionThresholdG: 0.035
    )

    public init(
        weights: ScoreWeights,
        targetSleepHours: ClosedRange<Double>,
        durationShortPenaltyPerHour: Double,
        durationLongPenaltyPerHour: Double,
        restlessnessMotionThresholdG: Double
    ) {
        self.weights = weights
        self.targetSleepHours = targetSleepHours
        self.durationShortPenaltyPerHour = durationShortPenaltyPerHour
        self.durationLongPenaltyPerHour = durationLongPenaltyPerHour
        self.restlessnessMotionThresholdG = restlessnessMotionThresholdG
    }
}

public struct SleepScoreEngine: SleepScoringModel {
    public var configuration: ScoringConfiguration

    public init(configuration: ScoringConfiguration = .default) {
        self.configuration = configuration
    }

    public func score(night: SleepNight, history: [SleepNight]) -> SleepScore {
        let duration = durationScore(night)
        let consistency = consistencyScore(night: night, history: history)
        let stages = stagesScore(night)
        let restlessness = restlessnessScore(night)
        let recovery = recoveryScore(night: night, history: history)
        let w = configuration.weights
        let weighted =
            duration * w.duration
            + consistency * w.consistency
            + stages * w.stages
            + restlessness * w.restlessness
            + recovery * w.recovery
        let normalised = w.total > 0 ? weighted / w.total : 0
        return SleepScore(
            total: Int(normalised.rounded()),
            duration: duration,
            consistency: consistency,
            stages: stages,
            restlessness: restlessness,
            recovery: recovery,
            weights: w
        )
    }

    public func durationScore(_ night: SleepNight) -> Double {
        let hours = night.asleepDuration / 3600
        let target = configuration.targetSleepHours
        if target.contains(hours) { return 100 }
        if hours < target.lowerBound {
            return Statistics.clamp(
                100 - configuration.durationShortPenaltyPerHour * (target.lowerBound - hours)
            )
        }
        return Statistics.clamp(
            100 - configuration.durationLongPenaltyPerHour * (hours - target.upperBound)
        )
    }

    public func consistencyScore(night: SleepNight, history: [SleepNight]) -> Double {
        let bedtimes = (history + [night])
            .suffix(8)
            .map { minutesFromMidnight($0.inBedStart) }
        guard bedtimes.count >= 3, let sd = Statistics.stddev(bedtimes.map(Double.init)) else {
            return 75
        }
        // Circular-ish wrap: if sd is inflated by midnight crossings, use min circular deviation.
        let circular = circularStddevMinutes(bedtimes)
        let used = min(sd, circular)
        if used <= 20 { return 100 }
        if used >= 90 { return 20 }
        return Statistics.clamp(100 - (used - 20) * (80.0 / 70.0))
    }

    public func stagesScore(_ night: SleepNight) -> Double {
        let asleep = night.asleepDuration
        guard asleep > 0 else { return 0 }
        if !night.hasDetailedStages {
            let efficiencyBoost = Statistics.clamp(night.sleepEfficiency * 100)
            return Statistics.clamp(0.55 * 72 + 0.45 * efficiencyBoost)
        }
        let deepPct = night.duration(for: .deep) / asleep * 100
        let remPct = night.duration(for: .rem) / asleep * 100
        let awakePct = night.inBedDuration > 0
            ? night.awakeDuration / night.inBedDuration * 100
            : 0
        let deep = Statistics.bandScore(deepPct, lowZero: 4, lowFull: 13, highFull: 23, highZero: 35)
        let rem = Statistics.bandScore(remPct, lowZero: 8, lowFull: 18, highFull: 25, highZero: 40)
        let awake = Statistics.lerpScore(value: awakePct, fullUntil: 6, zeroAt: 25)
        return Statistics.clamp(0.4 * deep + 0.4 * rem + 0.2 * awake)
    }

    public func restlessnessScore(_ night: SleepNight) -> Double {
        let wasoMinutes = night.waso / 60
        let wasoScore = Statistics.lerpScore(value: wasoMinutes, fullUntil: 15, zeroAt: 120)
        let threshold = configuration.restlessnessMotionThresholdG
        let restlessMinutes = night.motion.filter { $0.magnitude >= threshold }.count
        let motionPct: Double
        if night.motion.isEmpty {
            motionPct = wasoMinutes > 40 ? 25 : 8
        } else {
            motionPct = Double(restlessMinutes) / Double(max(1, night.motion.count)) * 100
        }
        let motionScore = Statistics.lerpScore(value: motionPct, fullUntil: 6, zeroAt: 35)
        return Statistics.clamp(0.6 * wasoScore + 0.4 * motionScore)
    }

    public func recoveryScore(night: SleepNight, history: [SleepNight]) -> Double {
        let hrValues = night.heartRateBPM.map(\.value)
        let hrvValues = night.hrvSDNN.map(\.value)
        if hrValues.isEmpty && hrvValues.isEmpty { return 70 }

        var parts: [Double] = []
        if let meanHR = Statistics.mean(hrValues) {
            // Quiet overnight HR typically 48–65 for many adults; not a medical cutoff.
            parts.append(Statistics.bandScore(meanHR, lowZero: 38, lowFull: 48, highFull: 68, highZero: 90))
            let sorted = night.heartRateBPM.sorted { $0.date < $1.date }
            if let first = sorted.first?.date {
                let early = sorted.filter { $0.date < first.addingTimeInterval(30 * 60) }.map(\.value)
                let lateCutoff = night.inBedEnd.addingTimeInterval(-2 * 3600)
                let late = sorted.filter { $0.date >= lateCutoff }.map(\.value)
                if let e = Statistics.mean(early), let l = Statistics.mean(late) {
                    let drop = e - l
                    parts.append(Statistics.clamp(50 + drop * 6, min: 20, max: 100))
                }
            }
        }
        if let meanHRV = Statistics.mean(hrvValues) {
            let historyHRV = history.compactMap { Statistics.mean($0.hrvSDNN.map(\.value)) }
            if let baseline = Statistics.median(historyHRV), baseline > 0 {
                let ratio = meanHRV / baseline
                parts.append(Statistics.clamp(100 * min(1.15, ratio) / 1.15, min: 25, max: 100))
            } else {
                parts.append(Statistics.bandScore(meanHRV, lowZero: 15, lowFull: 35, highFull: 90, highZero: 160))
            }
        }
        return Statistics.mean(parts) ?? 70
    }

    private func minutesFromMidnight(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        return h * 60 + m
    }

    private func circularStddevMinutes(_ minutes: [Int]) -> Double {
        let radians = minutes.map { Double($0) / (24 * 60) * 2 * Double.pi }
        let sinMean = radians.map(sin).reduce(0, +) / Double(radians.count)
        let cosMean = radians.map(cos).reduce(0, +) / Double(radians.count)
        let r = (sinMean * sinMean + cosMean * cosMean).squareRoot()
        let sdRadians = sqrt(-2 * log(max(r, 1e-9)))
        return sdRadians / (2 * Double.pi) * 24 * 60
    }
}
