import CoreGraphics
import Testing

@testable import DisplayAnchor

@MainActor
struct DisplayMonitorTests {
    @Test func eventsStayIgnoredUntilTheLastOverlappingApplyWindowCloses() async throws {
        let monitor = DisplayMonitor()
        monitor.settleSeconds = { 1 }
        var settled = 0
        monitor.onDisplaysSettled = { settled += 1 }

        // Each window stays open for 1 s after its work returns.
        await monitor.performApplying {}
        try await Task.sleep(for: .milliseconds(500))
        await monitor.performApplying {}
        try await Task.sleep(for: .milliseconds(700))
        // First window closed, second still open.
        monitor.handleReconfiguration(flags: .setModeFlag)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(settled == 0)

        monitor.handleReconfiguration(flags: .setModeFlag)
        try await Task.sleep(for: .milliseconds(1500))
        #expect(settled == 1)
    }

    @Test func reconfigurationTrackingClearsAfterAllBegunDisplaysComplete() {
        let monitor = DisplayMonitor()
        monitor.activeDisplayIDs = { [101, 102] }

        monitor.handleReconfiguration(display: 101, flags: .beginConfigurationFlag)
        monitor.handleReconfiguration(display: 102, flags: .beginConfigurationFlag)
        #expect(monitor.isReconfiguring)

        monitor.handleReconfiguration(display: 101, flags: .setModeFlag)
        #expect(monitor.isReconfiguring)

        monitor.handleReconfiguration(display: 102, flags: .movedFlag)
        #expect(!monitor.isReconfiguring)
    }

    @Test func reconfigurationDropsDisconnectedDisplaysAndFiresCompletion() async throws {
        let monitor = DisplayMonitor()
        var liveIDs: [CGDirectDisplayID] = [101, 102]
        monitor.activeDisplayIDs = { liveIDs }
        monitor.settleSeconds = { 10 }
        var completed = 0
        monitor.onReconfigurationCompleted = { completed += 1 }

        monitor.handleReconfiguration(display: 102, flags: .beginConfigurationFlag)
        #expect(monitor.isReconfiguring)

        liveIDs = [101]
        monitor.handleReconfiguration(display: 101, flags: .removeFlag)
        #expect(!monitor.isReconfiguring)

        try await Task.sleep(for: .milliseconds(350))
        #expect(completed == 1)
    }

    @Test func onApplyFinishedFiresAfterOverlappingApplyWindowsClose() async throws {
        let monitor = DisplayMonitor()
        var finished = 0
        monitor.onApplyFinished = { finished += 1 }

        await monitor.performApplying {}
        try await Task.sleep(for: .milliseconds(500))
        await monitor.performApplying {}
        try await Task.sleep(for: .milliseconds(700))
        #expect(finished == 0)

        try await Task.sleep(for: .milliseconds(600))
        #expect(finished == 1)
    }

    @Test func beginConfigurationKeepsNewlyConnectedInactiveDisplayUntilCompletion() {
        let monitor = DisplayMonitor()
        var liveIDs: [CGDirectDisplayID] = [101]
        monitor.activeDisplayIDs = { liveIDs }

        monitor.handleReconfiguration(display: 103, flags: .beginConfigurationFlag)
        #expect(monitor.isReconfiguring)

        liveIDs = [101, 103]
        monitor.handleReconfiguration(display: 103, flags: .addFlag)
        #expect(!monitor.isReconfiguring)
    }
}
