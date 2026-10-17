import Foundation

public struct HeuristicFeatureExtractor: FeatureExtractor {
    public init() {}

    public func features(from night: SleepNight, history: [SleepNight]) -> SleepFeatureVector {
        let asleepHours = night.asleepDuration / 3600
        let deepPct = night.asleepDuration > 0 ? night.duration(for: .deep) / night.asleepDuration * 100 : 0
        let remPct = night.asleepDuration > 0 ? night.duration(for: .rem) / night.asleepDuration * 100 : 0
        let corePct = night.asleepDuration > 0 ? night.duration(for: .core) / night.asleepDuration * 100 : 0
        let spo2 = night.spo2Percent.map(\.value)
        let hr = night.heartRateBPM.map(\.value)
        let hrv = night.hrvSDNN.map(\.value)
        let rr = night.respiratoryRateBPM.map(\.value)
        let motionThreshold = ScoringConfiguration.default.restlessnessMotionThresholdG
        let restlessPct: Double
        if night.motion.isEmpty {
            restlessPct = 0
        } else {
            restlessPct = Double(night.motion.filter { $0.magnitude >= motionThreshold }.count)
                / Double(night.motion.count) * 100
        }
        var values: [String: Double] = [
            "asleepHours": asleepHours,
            "inBedHours": night.inBedDuration / 3600,
            "efficiency": night.sleepEfficiency,
            "wasoMinutes": night.waso / 60,
            "deepPercent": deepPct,
            "remPercent": remPct,
            "corePercent": corePct,
            "meanHeartRate": Statistics.mean(hr) ?? 0,
            "meanHRV": Statistics.mean(hrv) ?? 0,
            "meanSpO2": Statistics.mean(spo2) ?? 0,
            "minSpO2": spo2.min() ?? 0,
            "spo2Range": (spo2.max() ?? 0) - (spo2.min() ?? 0),
            "meanRespiratoryRate": Statistics.mean(rr) ?? 0,
            "rrCV": Statistics.coefficientOfVariation(rr) ?? 0,
            "restlessMotionPercent": restlessPct,
            "sampleCountHR": Double(hr.count),
            "sampleCountSpO2": Double(spo2.count),
            "sampleCountRR": Double(rr.count),
            "historyNights": Double(history.count),
            "hasDetailedStages": night.hasDetailedStages ? 1 : 0,
            "appleBDElevated": night.appleBreathingDisturbances?.classification == .elevated ? 1 : 0,
            "wristTempDeltaC": night.wristTemperatureDeltaC?.value ?? 0
        ]
        if let last = history.last {
            values["priorAsleepHours"] = last.asleepDuration / 3600
        }
        return SleepFeatureVector(values: values)
    }
}
