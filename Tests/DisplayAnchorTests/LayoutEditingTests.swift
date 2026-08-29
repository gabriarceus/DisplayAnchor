import CoreGraphics
import Foundation
import Testing
@testable import DisplayAnchor

struct LayoutEditingTests {
    private func display(
        uuid: String,
        origin: CGPoint = .zero,
        size: CGSize = CGSize(width: 1920, height: 1080),
        isMain: Bool = false
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            stableID: StableDisplayID(uuid: uuid, vendor: 1, model: 2, serial: 3, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0),
            name: uuid,
            originX: Int(origin.x), originY: Int(origin.y),
            mode: ModeDescriptor(width: Int(size.width), height: Int(size.height), pixelWidth: Int(size.width), pixelHeight: Int(size.height), refresh: 60, ioFlags: 0),
            isMain: isMain, mirrorOfUUID: nil, rotation: 0
        )
    }

    @Test func snapPrefersNearestCandidateOnEachAxis() {
        let dragged = CGRect(x: 95, y: 205, width: 100, height: 100)
        let other = CGRect(x: 200, y: 200, width: 300, height: 300)

        #expect(LayoutEditing.snap(dragged, among: [other], threshold: 10) == CGPoint(x: 100, y: 200))
    }

    @Test func snapLeavesDistantEdgesUntouched() {
        let dragged = CGRect(x: 20, y: 30, width: 100, height: 100)
        let other = CGRect(x: 500, y: 500, width: 100, height: 100)

        #expect(LayoutEditing.snap(dragged, among: [other], threshold: 10) == dragged.origin)
    }

    @Test func overlapResolutionPushesAlongLeastPenetratedAxis() {
        let dragged = CGRect(x: 90, y: 0, width: 100, height: 100)
        let other = CGRect(x: 100, y: 0, width: 100, height: 100)

        let resolved = LayoutEditing.resolveOverlap(dragged, among: [other])
        #expect(resolved == CGPoint(x: 0, y: 0))
        #expect(!CGRect(origin: resolved, size: dragged.size).intersects(other))
    }

    @Test func profileKeepsDisplayAttributesAndUpdatesEditableFields() {
        let base = [display(uuid: "main", isMain: true), display(uuid: "side", origin: CGPoint(x: 1920, y: 0))]
        var draft = LayoutEditing.seed(from: base)
        draft[0].origin = CGPoint(x: 20, y: 30)
        draft[0].isMain = false
        draft[1].isMain = true

        let profile = LayoutEditing.profile(from: draft, base: base, fingerprint: "fixture")
        #expect(profile.fingerprint == "fixture")
        #expect(profile.displays[0].originX == 20)
        #expect(profile.displays[0].originY == 30)
        #expect(!profile.displays[0].isMain)
        #expect(profile.displays[1].isMain)
        #expect(profile.displays[0].mode == base[0].mode)
    }

    @Test func stableIdentityUsesUUIDBeforeEDIDFallback() {
        let identified = StableDisplayID(uuid: "uuid", vendor: 1, model: 2, serial: 3, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0)
        let fallback = StableDisplayID(uuid: nil, vendor: 1, model: 2, serial: 3, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0)

        #expect(identified.identityKey == "uuid")
        #expect(fallback.identityKey == "1:2:3:false")
    }
}
