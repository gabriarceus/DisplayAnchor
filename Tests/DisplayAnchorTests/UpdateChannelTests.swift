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

    @Test func channelCheckWaitsWhenSparkleAllowsUserChecksDuringAnActiveSession() {
        let updater = SessionUpdater()
        let controller = UpdateController(config: AppConfig(), updater: updater)
        updater.hasActiveSession = true

        controller.updateChannelChanged()
        controller.checkNow()

        #expect(updater.canCheckForUpdates)
        #expect(!controller.canCheck)
        #expect(updater.probeAttempts == 0)
        #expect(controller.status == .idle)
    }

    @Test func queuedChannelCheckRunsAfterTheActiveSessionFinishes() async {
        let name = "UpdateChannelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let config = AppConfig(defaults: defaults)
        let updater = SessionUpdater()
        let controller = UpdateController(config: config, updater: updater)
        updater.hasActiveSession = true

        config.updateChannelRaw = UpdateChannel.releaseCandidate.rawValue
        controller.updateChannelChanged()
        config.updateChannelRaw = UpdateChannel.stable.rawValue
        controller.updateChannelChanged()
        let noUpdate = NSError(
            domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))
        controller.updaterDidNotFindUpdate(updater, error: noUpdate)
        #expect(controller.status == .idle)
        #expect(updater.probeAttempts == 0)

        updater.hasActiveSession = false
        await withCheckedContinuation { continuation in
            updater.onProbe = { continuation.resume() }
            controller.updater(updater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)
        }

        #expect(updater.probeAttempts == 1)
        #expect(controller.allowedChannels(for: updater).isEmpty)
        #expect(controller.status == .checking)
        controller.updaterDidNotFindUpdate(updater, error: noUpdate)
        #expect(controller.status == .upToDate)
    }
}

@MainActor
private final class SessionUpdater: SPUUpdater {
    var hasActiveSession = false
    private(set) var probeAttempts = 0
    var onProbe: (() -> Void)?

    override var canCheckForUpdates: Bool { true }
    override var sessionInProgress: Bool { hasActiveSession }

    init() {
        super.init(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: SPUStandardUserDriver(hostBundle: .main, delegate: nil),
            delegate: nil)
    }

    override func checkForUpdateInformation() {
        probeAttempts += 1
        guard !hasActiveSession else { return }
        let callback = onProbe
        onProbe = nil
        callback?()
    }
}
