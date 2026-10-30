import Foundation
import Sparkle
import Testing

@testable import DisplayAnchor

@MainActor
struct UpdateControllerTests {
    @Test func noUpdateCompletionPreservesUpToDateStatus() {
        let controller = UpdateController(config: AppConfig())
        let updater = makeUpdater()
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))

        controller.updaterDidNotFindUpdate(updater, error: error)
        controller.updater(updater, didAbortWithError: error)

        #expect(controller.status == .upToDate)
    }

    @Test func networkFailureReportsFailedStatus() {
        let controller = UpdateController(config: AppConfig())
        let updater = makeUpdater()

        controller.updater(updater, didAbortWithError: URLError(.notConnectedToInternet))

        #expect(controller.status == .failed)
    }

    @Test func matchingCodeInAnotherDomainStillReportsFailure() {
        let controller = UpdateController(config: AppConfig())
        let updater = makeUpdater()
        let error = NSError(domain: NSURLErrorDomain, code: Int(SUError.noUpdateError.rawValue))

        controller.updater(updater, didAbortWithError: error)

        #expect(controller.status == .failed)
    }

    private func makeUpdater() -> SPUUpdater {
        SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: SPUStandardUserDriver(hostBundle: .main, delegate: nil),
            delegate: nil
        )
    }
}
