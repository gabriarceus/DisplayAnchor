import Foundation
import Testing
@testable import DisplayAnchor

@MainActor
struct ProfileStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProfileStoreTests-\(UUID().uuidString)", isDirectory: true)
    private var fileURL: URL { directory.appendingPathComponent("profiles.json") }

    private func profile(_ fingerprint: String, label: String = "Desk") -> LayoutProfile {
        LayoutProfile(
            fingerprint: fingerprint,
            label: label,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            displays: [
                DisplaySnapshot(
                    stableID: StableDisplayID(uuid: "u1", vendor: 1, model: 2, serial: 3, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0),
                    name: "Display",
                    originX: -1920, originY: 0,
                    mode: ModeDescriptor(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refresh: 60, ioFlags: 0),
                    isMain: true, mirrorOfUUID: nil, rotation: 90
                ),
            ]
        )
    }

    private func writeFile(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL)
    }

    /// Makes the directory read-only for `body`, so moves and atomic writes in it fail.
    private func withReadOnlyDirectory(_ body: () throws -> Void) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        try body()
    }

    private func cleanUp() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func savedProfilesSurviveARelaunch() {
        defer { cleanUp() }
        let saved = profile("fp")
        #expect(ProfileStore(directory: directory).save(saved))

        let reloaded = ProfileStore(directory: directory)
        #expect(reloaded.profiles == ["fp": saved])
        #expect(reloaded.issue == nil)
    }

    @Test func unreadableDocumentIsBackedUpBeforeANewListStarts() throws {
        defer { cleanUp() }
        try writeFile("not json")

        let store = ProfileStore(directory: directory)
        #expect(store.issue == .unreadableDocument)
        #expect(store.profiles.isEmpty)
        #expect(store.save(profile("fp")))

        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("profiles.corrupt-") }
        #expect(backups.count == 1)
        let backup = directory.appendingPathComponent(try #require(backups.first))
        #expect(try String(contentsOf: backup, encoding: .utf8) == "not json")
    }

    @Test func unreadableDocumentThatCannotBeBackedUpIsNeverOverwritten() throws {
        defer { cleanUp() }
        try writeFile("not json")

        var store: ProfileStore?
        try withReadOnlyDirectory { store = ProfileStore(directory: directory) }
        #expect(store?.issue == .storageUnavailable)

        // The backup failed only at launch; a later save must still not replace the file.
        #expect(store?.save(profile("fp")) == false)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "not json")
    }

    @Test func documentFromANewerVersionIsNeverOverwritten() throws {
        defer { cleanUp() }
        let newer = #"{"version": 2, "profiles": {}, "windows": []}"#
        try writeFile(newer)

        let store = ProfileStore(directory: directory)
        #expect(store.issue == .unsupportedDocumentVersion)
        #expect(!store.save(profile("fp")))
        #expect(!store.delete(fingerprint: "fp"))
        #expect(store.issue == .unsupportedDocumentVersion)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == newer)
    }

    @Test func failedWriteKeepsThePreviousLayouts() throws {
        defer { cleanUp() }
        let original = profile("fp", label: "Original")
        let store = ProfileStore(directory: directory)
        #expect(store.save(original))

        try withReadOnlyDirectory {
            #expect(!store.save(profile("other")))
            #expect(!store.rename(fingerprint: "fp", to: "Renamed"))
        }
        #expect(store.issue == .writeFailed)
        #expect(store.profiles == ["fp": original])
        #expect(ProfileStore(directory: directory).profiles == ["fp": original])
    }
}
