import Foundation
import Observation
import SleepCoachAnalysis
import WatchConnectivity
import WatchKit

@Observable
@MainActor
final class WatchModel {
    var isRunning = false
    var startedAt: Date?
    var lastScore: Int?
    var status: String = "Ready"
    var useSampleScore: Bool

    let session = SleepSessionManager()

    init() {
        useSampleScore = UserDefaults.standard.object(forKey: "useSampleScore") as? Bool ?? true
        lastScore = UserDefaults.standard.object(forKey: "lastNightScore") as? Int
        if lastScore == nil && useSampleScore {
            lastScore = 86
        }
        session.onStateChange = { [weak self] running, started in
            self?.isRunning = running
            self?.startedAt = started
            self?.status = running ? "Recording overnight session" : "Ready"
        }
        session.onScore = { [weak self] score in
            self?.lastScore = score
            UserDefaults.standard.set(score, forKey: "lastNightScore")
        }
        session.activate()
    }

    func toggle() {
        if isRunning {
            session.stop()
        } else {
            session.start()
            useSampleScore = false
        }
    }
}
