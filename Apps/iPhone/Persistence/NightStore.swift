import Foundation
import SleepCoachAnalysis

struct NightStore {
    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AISleepCoach", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var draftsURL: URL { folder.appendingPathComponent("session-drafts.json") }
    private var scoreURL: URL { folder.appendingPathComponent("last-score.json") }

    func loadDrafts() -> [SleepSessionDraft] {
        guard let data = try? Data(contentsOf: draftsURL) else { return [] }
        return (try? JSONDecoder().decode([SleepSessionDraft].self, from: data)) ?? []
    }

    func save(draft: SleepSessionDraft) {
        var drafts = loadDrafts()
        drafts.removeAll { $0.id == draft.id }
        drafts.append(draft)
        drafts = Array(drafts.suffix(45))
        if let data = try? JSONEncoder().encode(drafts) {
            try? data.write(to: draftsURL, options: [.atomic])
        }
    }

    func saveLastScore(_ score: Int) {
        let payload = ["score": score]
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: scoreURL, options: [.atomic])
        }
        UserDefaults.standard.set(score, forKey: "lastNightScore")
    }
}
