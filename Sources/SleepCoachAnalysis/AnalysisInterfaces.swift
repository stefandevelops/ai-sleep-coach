import Foundation

/// Scoring a night of sleep. Implementations must be deterministic for a given
/// night + history so unit tests can lock behaviour.
public protocol SleepScoringModel: Sendable {
    func score(night: SleepNight, history: [SleepNight]) -> SleepScore
}

/// Detects *possible* breathing disturbances. Must never claim a diagnosis.
public protocol BreathingDisturbanceDetector: Sendable {
    func detect(in night: SleepNight) -> [FlaggedEvent]
}

public protocol FeatureExtractor: Sendable {
    func features(from night: SleepNight, history: [SleepNight]) -> SleepFeatureVector
}

public protocol InsightGenerating: Sendable {
    func insights(
        night: SleepNight,
        history: [SleepNight],
        score: SleepScore,
        events: [FlaggedEvent]
    ) -> [Insight]
}

/// Stable app-facing interface. A future `CoreMLSleepAnalysisModel` can
/// conform to this without changing SwiftUI view models.
public protocol SleepAnalysisModel: Sendable {
    func analyze(night: SleepNight, history: [SleepNight]) -> SleepAnalysisResult
}

/// Placeholder for a later `.mlmodel`. The heuristic model is the default.
public protocol CoreMLSleepModelLoading: Sendable {
    var isAvailable: Bool { get }
}
