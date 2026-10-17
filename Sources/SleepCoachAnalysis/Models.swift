import Foundation

/// Where a night’s signals came from. Used so Apple Watch sleep is preferred
/// over the coach’s inferred stages, avoiding duplicate HealthKit writes.
public enum DataSource: String, Codable, Sendable, Equatable, CaseIterable {
    case appleWatch
    case aiSleepCoachSession
    case merged
    case sample
    case unknown
}

public enum SleepStage: String, Codable, Sendable, Equatable, CaseIterable {
    case inBed
    case awake
    case asleepUnspecified
    case core
    case deep
    case rem

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem:
            return true
        case .inBed, .awake:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .inBed: return "In bed"
        case .awake: return "Awake"
        case .asleepUnspecified: return "Asleep"
        case .core: return "Core"
        case .deep: return "Deep"
        case .rem: return "REM"
        }
    }
}

public struct SleepStageInterval: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    public var source: DataSource

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        stage: SleepStage,
        source: DataSource
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.source = source
    }

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

public struct TimedSample: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var value: Double

    public init(id: UUID = UUID(), date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}

public struct MotionSample: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    /// Peak acceleration magnitude in g during this minute.
    public var magnitude: Double
    /// Seconds in the minute that exceeded the restlessness threshold.
    public var activeSeconds: Int

    public init(
        id: UUID = UUID(),
        date: Date,
        magnitude: Double,
        activeSeconds: Int
    ) {
        self.id = id
        self.date = date
        self.magnitude = magnitude
        self.activeSeconds = activeSeconds
    }
}

public enum AppleBreathingDisturbancesClassification: String, Codable, Sendable, Equatable {
    case notElevated
    case elevated
    case unknown
}

/// Apple Watch “Breathing Disturbances” nightly reading from HealthKit.
/// Sleep Apnoea *notifications* are a system feature; HealthKit exposes the
/// underlying breathing-disturbance quantity, not a diagnosis.
public struct AppleBreathingDisturbancesReading: Codable, Sendable, Equatable {
    public var date: Date
    public var quantityValue: Double?
    public var classification: AppleBreathingDisturbancesClassification

    public init(
        date: Date,
        quantityValue: Double?,
        classification: AppleBreathingDisturbancesClassification
    ) {
        self.date = date
        self.quantityValue = quantityValue
        self.classification = classification
    }
}

public struct NightProvenance: Codable, Sendable, Equatable {
    public var sleepStagesSource: DataSource
    public var vitalsSource: DataSource
    public var motionSource: DataSource

    public init(
        sleepStagesSource: DataSource,
        vitalsSource: DataSource,
        motionSource: DataSource
    ) {
        self.sleepStagesSource = sleepStagesSource
        self.vitalsSource = vitalsSource
        self.motionSource = motionSource
    }
}

/// One overnight period, typically “last night” ending on `wakeDate`.
public struct SleepNight: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Calendar date of the morning this night ended (device-local when created).
    public var morningDate: Date
    public var inBedStart: Date
    public var inBedEnd: Date
    public var stages: [SleepStageInterval]
    public var heartRateBPM: [TimedSample]
    public var hrvSDNN: [TimedSample]
    public var spo2Percent: [TimedSample]
    public var respiratoryRateBPM: [TimedSample]
    public var wristTemperatureDeltaC: TimedSample?
    public var motion: [MotionSample]
    public var appleBreathingDisturbances: AppleBreathingDisturbancesReading?
    public var provenance: NightProvenance
    /// True when this night was synthesised for Simulator / preview.
    public var isSampleData: Bool

    public init(
        id: UUID = UUID(),
        morningDate: Date,
        inBedStart: Date,
        inBedEnd: Date,
        stages: [SleepStageInterval],
        heartRateBPM: [TimedSample] = [],
        hrvSDNN: [TimedSample] = [],
        spo2Percent: [TimedSample] = [],
        respiratoryRateBPM: [TimedSample] = [],
        wristTemperatureDeltaC: TimedSample? = nil,
        motion: [MotionSample] = [],
        appleBreathingDisturbances: AppleBreathingDisturbancesReading? = nil,
        provenance: NightProvenance,
        isSampleData: Bool = false
    ) {
        self.id = id
        self.morningDate = morningDate
        self.inBedStart = inBedStart
        self.inBedEnd = inBedEnd
        self.stages = stages
        self.heartRateBPM = heartRateBPM
        self.hrvSDNN = hrvSDNN
        self.spo2Percent = spo2Percent
        self.respiratoryRateBPM = respiratoryRateBPM
        self.wristTemperatureDeltaC = wristTemperatureDeltaC
        self.motion = motion
        self.appleBreathingDisturbances = appleBreathingDisturbances
        self.provenance = provenance
        self.isSampleData = isSampleData
    }

    public var inBedDuration: TimeInterval {
        max(0, inBedEnd.timeIntervalSince(inBedStart))
    }

    public var asleepDuration: TimeInterval {
        stages.filter { $0.stage.isAsleep }.reduce(0) { $0 + $1.duration }
    }

    public var awakeDuration: TimeInterval {
        stages.filter { $0.stage == .awake }.reduce(0) { $0 + $1.duration }
    }

    public var sleepEfficiency: Double {
        guard inBedDuration > 0 else { return 0 }
        return min(1, asleepDuration / inBedDuration)
    }

    public var hasDetailedStages: Bool {
        stages.contains { $0.stage == .core || $0.stage == .deep || $0.stage == .rem }
    }

    public func duration(for stage: SleepStage) -> TimeInterval {
        stages.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    /// Wake after sleep onset, in seconds.
    public var waso: TimeInterval {
        let sleepIntervals = stages.filter(\.stage.isAsleep).sorted { $0.start < $1.start }
        guard let firstSleep = sleepIntervals.first else { return awakeDuration }
        return stages
            .filter { $0.stage == .awake && $0.start >= firstSleep.start }
            .reduce(0) { $0 + $1.duration }
    }
}

public struct ScoreWeights: Codable, Sendable, Equatable {
    public var duration: Double
    public var consistency: Double
    public var stages: Double
    public var restlessness: Double
    public var recovery: Double

    public static let `default` = ScoreWeights(
        duration: 0.30,
        consistency: 0.15,
        stages: 0.20,
        restlessness: 0.15,
        recovery: 0.20
    )

    public var total: Double {
        duration + consistency + stages + restlessness + recovery
    }

    public init(
        duration: Double,
        consistency: Double,
        stages: Double,
        restlessness: Double,
        recovery: Double
    ) {
        self.duration = duration
        self.consistency = consistency
        self.stages = stages
        self.restlessness = restlessness
        self.recovery = recovery
    }
}

public struct SleepScore: Codable, Sendable, Equatable {
    /// Integer 0–100 presented in the UI.
    public var total: Int
    public var duration: Double
    public var consistency: Double
    public var stages: Double
    public var restlessness: Double
    public var recovery: Double
    public var weights: ScoreWeights

    public init(
        total: Int,
        duration: Double,
        consistency: Double,
        stages: Double,
        restlessness: Double,
        recovery: Double,
        weights: ScoreWeights = .default
    ) {
        self.total = min(100, max(0, total))
        self.duration = duration
        self.consistency = consistency
        self.stages = stages
        self.restlessness = restlessness
        self.recovery = recovery
        self.weights = weights
    }
}

public enum InsightCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case duration
    case consistency
    case stages
    case restlessness
    case recovery
    case breathing
    case appleHealth
    case dataQuality
}

public struct Insight: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var body: String
    public var category: InsightCategory

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        category: InsightCategory
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
    }
}

public enum FlaggedEventKind: String, Codable, Sendable, Equatable, CaseIterable {
    case possibleSpO2Dip
    case respiratoryIrregularity
    case heartRatePattern
    case combinedBreathingPattern
    case appleElevatedBreathingDisturbances
}

public enum FlagSeverity: String, Codable, Sendable, Equatable, Comparable {
    case low
    case moderate
    case high

    public static func < (lhs: FlagSeverity, rhs: FlagSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    var rank: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        }
    }
}

public struct FlaggedEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var duration: TimeInterval
    public var kind: FlaggedEventKind
    public var severity: FlagSeverity
    public var explanation: String
    public var supportingSignals: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        duration: TimeInterval,
        kind: FlaggedEventKind,
        severity: FlagSeverity,
        explanation: String,
        supportingSignals: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.kind = kind
        self.severity = severity
        self.explanation = explanation
        self.supportingSignals = supportingSignals
    }
}

public struct SleepAnalysisResult: Codable, Sendable, Equatable {
    public var nightID: UUID
    public var score: SleepScore
    public var insights: [Insight]
    public var flaggedEvents: [FlaggedEvent]
    /// Heuristic “events per hour of sleep” — not an AHI and not a diagnosis.
    public var possibleDisturbanceIndex: Double
    public var featureVector: SleepFeatureVector

    public init(
        nightID: UUID,
        score: SleepScore,
        insights: [Insight],
        flaggedEvents: [FlaggedEvent],
        possibleDisturbanceIndex: Double,
        featureVector: SleepFeatureVector
    ) {
        self.nightID = nightID
        self.score = score
        self.insights = insights
        self.flaggedEvents = flaggedEvents
        self.possibleDisturbanceIndex = possibleDisturbanceIndex
        self.featureVector = featureVector
    }
}

/// Named numeric features so a Core ML model can be swapped in later
/// without changing the app’s night → result interface.
public struct SleepFeatureVector: Codable, Sendable, Equatable {
    public var values: [String: Double]

    public init(values: [String: Double]) {
        self.values = values
    }

    public subscript(_ key: String) -> Double? {
        values[key]
    }
}
