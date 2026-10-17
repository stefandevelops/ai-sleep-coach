import Foundation
import SleepCoachAnalysis
import WatchConnectivity

@MainActor
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    var onDraft: ((SleepSessionDraft) -> Void)?
    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    func updateApplicationContext(lastScore: Int?, morning: Date?) {
        guard let session, session.activationState == .activated else { return }
        var context: [String: Any] = [:]
        if let lastScore { context["lastScore"] = lastScore }
        if let morning { context["morning"] = morning }
        try? session.updateApplicationContext(context)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage data: [String: Any]) {
        decodeDraft(from: data)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        decodeDraft(from: userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        decodeDraft(fromData: data)
    }

    private nonisolated func decodeDraft(from dictionary: [String: Any]) {
        guard let data = dictionary["draft"] as? Data else { return }
        decodeDraft(fromData: data)
    }

    private nonisolated func decodeDraft(fromData data: Data) {
        guard let draft = try? JSONDecoder().decode(SleepSessionDraft.self, from: data) else { return }
        Task { @MainActor in
            onDraft?(draft)
        }
    }
}
