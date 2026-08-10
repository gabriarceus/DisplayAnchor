import Foundation

/// On-disk document of saved layout profiles, keyed by display-set fingerprint.
/// `version` allows forward migration (e.g. a future window-position extension).
struct ProfileDocument: Codable {
    var version: Int
    var profiles: [String: LayoutProfile]
}

/// JSON persistence of layout profiles in Application Support. The whole document
/// is loaded once at init and rewritten atomically on every mutation.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [String: LayoutProfile] = [:]

    private static let currentVersion = 1
    private let fileURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("DisplayAnchor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("profiles.json")
        load()
    }

    func profile(for fingerprint: String) -> LayoutProfile? { profiles[fingerprint] }

    func save(_ profile: LayoutProfile) {
        profiles[profile.fingerprint] = profile
        persist()
    }

    func delete(fingerprint: String) {
        profiles.removeValue(forKey: fingerprint)
        persist()
    }

    func rename(fingerprint: String, to label: String) {
        guard var profile = profiles[fingerprint] else { return }
        profile.label = label
        profiles[fingerprint] = profile
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? decoder.decode(ProfileDocument.self, from: data)
        else { return }
        profiles = document.profiles
    }

    private func persist() {
        let document = ProfileDocument(version: Self.currentVersion, profiles: profiles)
        guard let data = try? encoder.encode(document) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
