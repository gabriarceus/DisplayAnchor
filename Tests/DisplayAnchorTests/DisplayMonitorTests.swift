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
}
