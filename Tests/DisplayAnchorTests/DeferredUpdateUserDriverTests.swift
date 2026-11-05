import Foundation
import Sparkle
import Testing

@testable import DisplayAnchor

@MainActor
struct DeferredUpdateUserDriverTests {
    private func makeDriver(mayPresentUpdate: Bool = true) -> DeferredUpdateUserDriver {
        let name = "DeferredUpdateUserDriverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return DeferredUpdateUserDriver(config: AppConfig(defaults: defaults), mayPresentUpdate: { mayPresentUpdate })
    }

    private func item(channel: String? = nil) throws -> SUAppcastItem {
        var dictionary: [String: Any] = [
            "sparkle:version": "6",
            "sparkle:shortVersionString": "1.1.0",
            "enclosure": ["url": "https://example.invalid/update.zip"],
        ]
        if let channel { dictionary["sparkle:channel"] = channel }
        return try #require(SUAppcastItem(dictionary: dictionary))
    }

    private func scheduledState() throws -> SPUUserUpdateState {
        try #require(SPUUserUpdateState(coder: ScheduledUpdateDecoder()))
    }

    @Test func scheduledOfferStaysSilentAndDismissesOnlyOnce() throws {
        let driver = makeDriver()
        var replies: [SPUUserUpdateChoice] = []

        driver.showUpdateFound(with: try item(), state: try scheduledState()) { replies.append($0) }
        #expect(replies.isEmpty)
        driver.dismissPendingUpdate()
        driver.dismissPendingUpdate()
        #expect(replies == [.dismiss])
    }

    @Test func offerFromAnUnselectedChannelIsDismissedAtOnce() throws {
        let driver = makeDriver()
        var replies: [SPUUserUpdateChoice] = []

        driver.showUpdateFound(with: try item(channel: "rc"), state: try scheduledState()) { replies.append($0) }
        #expect(replies == [.dismiss])
    }

    @Test func offerDuringAPendingChannelCheckIsDismissedAtOnce() throws {
        let driver = makeDriver(mayPresentUpdate: false)
        var replies: [SPUUserUpdateChoice] = []

        driver.showUpdateFound(with: try item(), state: try scheduledState()) { replies.append($0) }
        #expect(replies == [.dismiss])
    }
}

/// Decodes an `SPUUserUpdateState` for an update found by a scheduled check, not yet downloaded.
final class ScheduledUpdateDecoder: NSCoder {
    override var allowsKeyedCoding: Bool { true }
    override func decodeInteger(forKey key: String) -> Int {
        SPUUserUpdateStage.notDownloaded.rawValue
    }
    override func decodeBool(forKey key: String) -> Bool { false }
}
