import Foundation

/// Default on-device model: score + heuristic detector + insights.
/// Swap this type for a Core ML-backed model that still returns `SleepAnalysisResult`.
public struct HeuristicSleepAnalysisModel: SleepAnalysisModel {
    public var scorer: SleepScoreEngine
    public var breathingDetector: BreathingDisturbanceHeuristic
    public var features: HeuristicFeatureExtractor
    public var insightGenerator: InsightGenerator

    public init(
        scorer: SleepScoreEngine = SleepScoreEngine(),
        breathingDetector: BreathingDisturbanceHeuristic = BreathingDisturbanceHeuristic(),
        features: HeuristicFeatureExtractor = HeuristicFeatureExtractor(),
        insightGenerator: InsightGenerator = InsightGenerator()
    ) {
        self.scorer = scorer
        self.breathingDetector = breathingDetector
        self.features = features
        self.insightGenerator = insightGenerator
    }

    public func analyze(night: SleepNight, history: [SleepNight]) -> SleepAnalysisResult {
        let score = scorer.score(night: night, history: history)
        let events = breathingDetector.detect(in: night)
        let vector = features.features(from: night, history: history)
        let insights = insightGenerator.insights(
            night: night,
            history: history,
            score: score,
            events: events
        )
        let hours = max(night.asleepDuration / 3600, 0.25)
        let counted = events.filter { $0.kind != .appleElevatedBreathingDisturbances }
        return SleepAnalysisResult(
            nightID: night.id,
            score: score,
            insights: insights,
            flaggedEvents: events,
            possibleDisturbanceIndex: Double(counted.count) / hours,
            featureVector: vector
        )
    }
}

/// Documents how a Core ML model would plug in. Always unavailable until a
/// compiled `.mlmodel` is added to the app target.
public struct UnavailabilityCoreMLSleepModel: CoreMLSleepModelLoading {
    public init() {}
    public var isAvailable: Bool { false }
}
