import Foundation
import Sparkle
import Testing

@testable import DisplayAnchor

@MainActor
struct UpdateChannelTests {
    @Test func stableIsTheDefaultAndUnknownValuesFallBackToStable() {
        let name = "UpdateChannelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(AppConfig(defaults: defaults).updateChannel == .stable)
        defaults.set("unknown", forKey: "updateChannel")
        #expect(AppConfig(defaults: defaults).updateChannel == .stable)
    }

    @Test func channelSelectionPersists() {
        let name = "UpdateChannelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let config = AppConfig(defaults: defaults)

        config.updateChannelRaw = UpdateChannel.releaseCandidate.rawValue

        #expect(AppConfig(defaults: defaults).updateChannel == .releaseCandidate)
    }

    @Test func stableRejectsRCAndOptInIncludesStable() {
        #expect(UpdateChannel.stable.allows(nil))
        #expect(!UpdateChannel.stable.allows("rc"))
        #expect(UpdateChannel.releaseCandidate.allows(nil))
        #expect(UpdateChannel.releaseCandidate.allows("rc"))
        #expect(!UpdateChannel.releaseCandidate.allows("beta"))
    }

    @Test func channelChangeClearsPendingRCAndRejectsOldResponses() throws {
        let name = "UpdateChannelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let config = AppConfig(defaults: defaults)
        config.updateChannelRaw = UpdateChannel.releaseCandidate.rawValue
        let controller = UpdateController(config: config)
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: SPUStandardUserDriver(hostBundle: .main, delegate: nil),
            delegate: nil
        )
        let candidate = try #require(
            SUAppcastItem(dictionary: [
                "sparkle:version": "6",
                "sparkle:shortVersionString": "1.1.0-rc4",
                "sparkle:channel": "rc",
                "enclosure": ["url": "https://example.invalid/update.zip"],
            ]))
        #expect(controller.allowedChannels(for: updater) == ["rc"])
        controller.updater(updater, didFindValidUpdate: candidate)
        #expect(controller.availableVersion == "1.1.0-rc4")

        config.updateChannelRaw = UpdateChannel.stable.rawValue
        controller.updateChannelChanged()
        controller.updater(updater, didFindValidUpdate: candidate)

        #expect(controller.allowedChannels(for: updater).isEmpty)
        #expect(controller.availableVersion == nil)
    }
}
