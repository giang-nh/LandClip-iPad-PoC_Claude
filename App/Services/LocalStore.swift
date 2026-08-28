import Foundation

/// The declared operator name — a lightweight identity, not authentication. Asked
/// once on first launch, remembered, re-asked if lost. Attached to ratings.
@MainActor
final class UserProfile: ObservableObject {
    @Published private(set) var name: String

    private let key = "landclip.userName"

    init() {
        name = (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
    }

    var hasName: Bool { !name.isEmpty }

    func setName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmed
        UserDefaults.standard.set(trimmed, forKey: key)
    }
}

/// Đúng/Sai ratings for clip results, per job. Persisted as JSON in Application
/// Support; never leaves the device. Rating does not touch the extracted data.
@MainActor
final class RatingStore: ObservableObject {
    enum Verdict: String, Codable { case correct, wrong }

    @Published private(set) var verdicts: [String: Verdict] = [:]

    private let fileURL: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("landclip-ratings.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Verdict].self, from: data) {
            verdicts = decoded
        }
    }

    func verdict(for key: String) -> Verdict? { verdicts[key] }

    func set(_ verdict: Verdict?, for key: String) {
        if let verdict { verdicts[key] = verdict } else { verdicts.removeValue(forKey: key) }
        try? JSONEncoder().encode(verdicts).write(to: fileURL, options: .atomic)
    }
}
