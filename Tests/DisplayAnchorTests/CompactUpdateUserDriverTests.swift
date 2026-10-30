import AppKit
import Foundation
import Sparkle
import Testing

@testable import DisplayAnchor

@MainActor
struct CompactUpdateUserDriverTests {
    @Test(arguments: ["en", "it"])
    func confirmationFitsACompactWindowAndKeepsAnExplicitChoice(language: String) throws {
        _ = NSApplication.shared
        let name = "CompactUpdateUserDriverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let config = AppConfig(defaults: defaults)
        config.appLanguageRaw = language
        let driver = CompactUpdateUserDriver(config: config, mayPresentUpdate: { true })
        let alert = driver.confirmationAlert(version: "1.1.0-rc3", stage: .notDownloaded)
        alert.layout()

        #expect(alert.messageText.contains("1.1.0-rc3"))
        #expect(
            alert.buttons.map(\.title)
                == (language == "en" ? ["Install", "Cancel"] : ["Installa", "Annulla"]))
        #expect(alert.window.frame.width < 500)
        #expect(alert.window.frame.height < 300)
    }

    @Test func scheduledOfferStaysSilentAndDismissesOnlyOnce() throws {
        let name = "CompactUpdateUserDriverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let driver = CompactUpdateUserDriver(
            config: AppConfig(defaults: defaults), mayPresentUpdate: { true })
        let item = try #require(
            SUAppcastItem(dictionary: [
                "sparkle:version": "6",
                "sparkle:shortVersionString": "1.1.0",
                "enclosure": ["url": "https://example.invalid/update.zip"],
            ]))
        let state = try #require(SPUUserUpdateState(coder: ScheduledUpdateDecoder()))
        var replies: [SPUUserUpdateChoice] = []

        driver.showUpdateFound(with: item, state: state) { replies.append($0) }
        #expect(replies.isEmpty)
        driver.dismissPendingUpdate()
        driver.dismissPendingUpdate()
        #expect(replies == [.dismiss])
    }
}

private final class ScheduledUpdateDecoder: NSCoder {
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int {
        SPUUserUpdateStage.notDownloaded.rawValue
    }
    override func decodeBool(forKey key: String) -> Bool { false }
}
