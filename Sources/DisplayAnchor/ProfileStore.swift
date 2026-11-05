import Foundation

/// On-disk document of saved layout profiles, keyed by display-set fingerprint.
/// `version` identifies the document format; other versions are never overwritten.
struct ProfileDocument: Codable {
    var version: Int
    var profiles: [String: LayoutProfile]
}

/// A recoverable problem accessing the local profile document. The exact system
/// error is written to the unified log; this value is safe to show in the UI.
enum ProfileStoreIssue: Equatable {
    case storageUnavailable
    case unreadableDocument
    case unsupportedDocumentVersion
    case writeFailed
}

/// JSON persistence of layout profiles in Application Support. The whole document
/// is loaded once at init and rewritten atomically on every mutation.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [String: LayoutProfile] = [:]
    @Published private(set) var issue: ProfileStoreIssue?

    private static let currentVersion = 1
    private var fileURL: URL?
    /// Never overwrite a document this version cannot safely replace: one from a
    /// newer app version (it may hold unknown fields), or an unreadable one that
    /// could not be backed up.
    private var writesAreBlocked = false

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

    /// Loads `profiles.json` from `directory`, creating the directory if needed.
    /// `nil` uses `~/Library/Application Support/DisplayAnchor`.
    init(directory: URL? = nil) {
        guard
            let directory = directory
                ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("DisplayAnchor", isDirectory: true)
        else {
            report(.storageUnavailable, "Application Support directory is unavailable")
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("profiles.json")
        } catch {
            report(.storageUnavailable, "Could not create profile directory: \(error.localizedDescription)")
            return
        }
        load()
    }

    func profile(for fingerprint: String) -> LayoutProfile? { profiles[fingerprint] }

    @discardableResult
    func save(_ profile: LayoutProfile) -> Bool {
        var proposed = profiles
        proposed[profile.fingerprint] = profile
        return commit(proposed)
    }

    @discardableResult
    func delete(fingerprint: String) -> Bool {
        var proposed = profiles
        proposed.removeValue(forKey: fingerprint)
        return commit(proposed)
    }

    @discardableResult
    func rename(fingerprint: String, to label: String) -> Bool {
        guard var profile = profiles[fingerprint] else { return false }
        profile.label = label
        var proposed = profiles
        proposed[fingerprint] = profile
        return commit(proposed)
    }

    private func load() {
        guard let fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try decoder.decode(ProfileDocument.self, from: data)
            guard document.version == Self.currentVersion else {
                writesAreBlocked = true
                report(.unsupportedDocumentVersion, "Unsupported profile document version \(document.version)")
                return
            }
            profiles = document.profiles
        } catch {
            Log.profiles.error("Could not decode profile document: \(error.localizedDescription, privacy: .public)")
            if backupUnreadableDocument(at: fileURL) {
                report(.unreadableDocument, "Starting with an empty profile list")
            } else {
                writesAreBlocked = true
                report(.storageUnavailable, "Profile writes blocked: the unreadable document is the only copy")
            }
        }
    }

    private func commit(_ proposed: [String: LayoutProfile]) -> Bool {
        // The issue that blocked writes is already reported; keep it visible.
        guard !writesAreBlocked else {
            Log.profiles.error("Refusing to overwrite a profile document that could not be loaded safely")
            return false
        }
        guard let fileURL else {
            report(.storageUnavailable, "Profile file URL is unavailable")
            return false
        }
        do {
            let document = ProfileDocument(version: Self.currentVersion, profiles: proposed)
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
            profiles = proposed
            issue = nil
            return true
        } catch {
            report(.writeFailed, "Could not write profile document: \(error.localizedDescription)")
            return false
        }
    }

    /// Moves malformed JSON to a timestamped sibling file. Returns false when the
    /// move fails, in which case the original file is still the only copy.
    private func backupUnreadableDocument(at fileURL: URL) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(formatter.string(from: Date())).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            Log.profiles.notice("Moved unreadable profile document to \(backupURL.lastPathComponent, privacy: .public)")
            return true
        } catch {
            Log.profiles.error(
                "Could not back up unreadable profile document: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func report(_ issue: ProfileStoreIssue, _ message: String) {
        self.issue = issue
        Log.profiles.error("\(message, privacy: .public)")
    }
}
