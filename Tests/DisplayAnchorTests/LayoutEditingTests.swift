import CoreGraphics
import Foundation
import Testing

@testable import DisplayAnchor

struct LayoutEditingTests {
    private func display(
        uuid: String,
        origin: CGPoint = .zero,
        size: CGSize = CGSize(width: 1920, height: 1080),
        isMain: Bool = false,
        rotation: Double = 0.0
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            stableID: StableDisplayID(
                uuid: uuid, vendor: 1, model: 2, serial: 3, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0),
            name: uuid,
            originX: Int(origin.x), originY: Int(origin.y),
            mode: ModeDescriptor(
                width: Int(size.width), height: Int(size.height), pixelWidth: Int(size.width),
                pixelHeight: Int(size.height), refresh: 60, ioFlags: 0),
            isMain: isMain, mirrorOfUUID: nil, rotation: rotation
        )
    }

    // MARK: - Snapping

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

    @Test func snapFlushesTopAndBottomEdges() {
        let other = CGRect(x: 200, y: 200, width: 300, height: 300)

        // Dragged bottom near other top (dragged y: 95, height: 100 -> bottom 195 vs 200)
        let draggedAbove = CGRect(x: 200, y: 95, width: 100, height: 100)
        #expect(LayoutEditing.snap(draggedAbove, among: [other], threshold: 10) == CGPoint(x: 200, y: 100))

        // Dragged top near other bottom (dragged y: 505 vs other bottom 500)
        let draggedBelow = CGRect(x: 200, y: 505, width: 100, height: 100)
        #expect(LayoutEditing.snap(draggedBelow, among: [other], threshold: 10) == CGPoint(x: 200, y: 500))
    }

    @Test func snapAlignsTopAndBottomEdges() {
        let other = CGRect(x: 200, y: 200, width: 300, height: 300)

        // Top edges aligned: dragged y: 205 vs other y: 200
        let draggedTop = CGRect(x: 50, y: 205, width: 100, height: 100)
        #expect(LayoutEditing.snap(draggedTop, among: [other], threshold: 10) == CGPoint(x: 50, y: 200))

        // Bottom edges aligned: dragged y: 395, height: 100 (bottom 495) vs other bottom 500 -> snaps to 400
        let draggedBottom = CGRect(x: 50, y: 395, width: 100, height: 100)
        #expect(LayoutEditing.snap(draggedBottom, among: [other], threshold: 10) == CGPoint(x: 50, y: 400))
    }

    @Test func snapRightFlushAndRightAligned() {
        let other = CGRect(x: 200, y: 200, width: 300, height: 300)

        // Right edge flush to other's left edge: dragged x: 95, width: 100 (right 195) vs other x: 200 -> snaps to 100
        let draggedLeft = CGRect(x: 95, y: 200, width: 100, height: 100)
        #expect(LayoutEditing.snap(draggedLeft, among: [other], threshold: 10) == CGPoint(x: 100, y: 200))

        // Right edges aligned: dragged x: 395, width: 100 (right 495) vs other right 500 -> snaps to 400
        let draggedRightAlign = CGRect(x: 395, y: 200, width: 100, height: 100)
        #expect(LayoutEditing.snap(draggedRightAlign, among: [other], threshold: 10) == CGPoint(x: 400, y: 200))
    }

    @Test func snapPicksClosestCandidateAmongMultipleObstacles() {
        let obstacleLeft = CGRect(x: 0, y: 0, width: 100, height: 100)  // right edge: 100
        let obstacleRight = CGRect(x: 215, y: 0, width: 100, height: 100)  // left edge: 215

        // Dragged at x: 103 (distance to left's right edge is 3; distance to right's left edge is 12)
        let dragged = CGRect(x: 103, y: 0, width: 100, height: 100)
        let snapped = LayoutEditing.snap(dragged, among: [obstacleLeft, obstacleRight], threshold: 15)
        #expect(snapped.x == 100)
    }

    // MARK: - Overlap Resolution

    @Test func overlapResolutionPushesAlongLeastPenetratedAxis() {
        // Horizontal penetration is 10, vertical is 100 -> pushes horizontally
        let dragged = CGRect(x: 90, y: 0, width: 100, height: 100)
        let other = CGRect(x: 100, y: 0, width: 100, height: 100)

        let resolved = LayoutEditing.resolveOverlap(dragged, among: [other])
        #expect(resolved == CGPoint(x: 0, y: 0))
        #expect(!CGRect(origin: resolved, size: dragged.size).intersects(other))
    }

    @Test func overlapResolutionPushesVerticallyWhenVerticalPenetrationIsSmaller() {
        // Vertical penetration is 10, horizontal is 100 -> pushes vertically
        let dragged = CGRect(x: 0, y: 90, width: 100, height: 100)
        let other = CGRect(x: 0, y: 100, width: 100, height: 100)

        let resolved = LayoutEditing.resolveOverlap(dragged, among: [other])
        #expect(resolved == CGPoint(x: 0, y: 0))
        #expect(!CGRect(origin: resolved, size: dragged.size).intersects(other))
    }

    @Test func overlapResolutionCascadesAcrossMultipleObstacles() {
        let obstacle1 = CGRect(x: 100, y: 0, width: 100, height: 100)
        let obstacle2 = CGRect(x: 0, y: 0, width: 100, height: 100)

        // Dragged placed right in obstacle 1, pushing left would hit obstacle 2 -> should resolve cleanly
        let dragged = CGRect(x: 105, y: 0, width: 100, height: 100)
        let resolved = LayoutEditing.resolveOverlap(dragged, among: [obstacle1, obstacle2])
        let resolvedRect = CGRect(origin: resolved, size: dragged.size)

        #expect(!resolvedRect.intersects(obstacle1))
        #expect(!resolvedRect.intersects(obstacle2))
    }

    // MARK: - Connectivity

    @Test func connectivityRequiresSharedEdgesNotCorners() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(LayoutEditing.isConnected([a, CGRect(x: 100, y: 50, width: 100, height: 100)]))
        #expect(!LayoutEditing.isConnected([a, CGRect(x: 100, y: 100, width: 100, height: 100)]))
        #expect(!LayoutEditing.isConnected([a, CGRect(x: 300, y: 0, width: 100, height: 100)]))
    }

    @Test func connectivityFollowsChains() {
        let chain = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 200, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        #expect(LayoutEditing.isConnected(chain))
    }

    @Test func attachMovesDetachedDisplayToNearestEdge() {
        let other = CGRect(x: 0, y: 0, width: 300, height: 200)
        let detached = CGRect(x: 400, y: 20, width: 100, height: 100)

        #expect(LayoutEditing.attach(detached, among: [other], minimumSharedEdge: 50) == CGPoint(x: 300, y: 20))
    }

    @Test func attachKeepsMinimumSharedEdge() {
        let other = CGRect(x: 0, y: 0, width: 300, height: 200)
        let farBelowRight = CGRect(x: 400, y: 500, width: 100, height: 100)

        #expect(LayoutEditing.attach(farBelowRight, among: [other], minimumSharedEdge: 50) == CGPoint(x: 250, y: 200))
    }

    @Test func attachFailsWhenOthersStayDisconnected() {
        let others = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 1000, y: 0, width: 100, height: 100)]
        let dragged = CGRect(x: 0, y: 500, width: 100, height: 100)

        #expect(LayoutEditing.attach(dragged, among: others, minimumSharedEdge: 50) == nil)
    }

    // MARK: - Seeding and Profile Reconstitution

    @Test func seedClampsZeroOrNegativeDimensionsToAtLeastOne() {
        let baseDisplay = display(uuid: "d-zero", size: CGSize(width: 0, height: -10))
        let drafts = LayoutEditing.seed(from: [baseDisplay])

        #expect(drafts.count == 1)
        #expect(drafts[0].size.width == 1.0)
        #expect(drafts[0].size.height == 1.0)
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

    @Test func profileRoundsFractionalOriginsAndPrunesUnknownDrafts() {
        let base = [display(uuid: "main", isMain: true)]
        var draft = LayoutEditing.seed(from: base)
        draft[0].origin = CGPoint(x: 100.6, y: 199.4)

        // Add a rogue draft display not in base
        let rogueDraft = DraftDisplay(
            stableID: StableDisplayID(
                uuid: "rogue", vendor: 9, model: 9, serial: 9, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0),
            name: "Rogue",
            origin: .zero,
            size: CGSize(width: 100, height: 100),
            isMain: false
        )
        draft.append(rogueDraft)

        let profile = LayoutEditing.profile(from: draft, base: base, fingerprint: "fp")
        #expect(profile.displays.count == 1)
        #expect(profile.displays[0].originX == 101)
        #expect(profile.displays[0].originY == 199)
    }

    @Test func indistinguishableDisplaysKeepSeparateDrafts() {
        var left = display(uuid: "same", isMain: true)
        var right = display(uuid: "same", origin: CGPoint(x: 1920, y: 0))
        left.stableID.ambiguityOrdinal = 0
        right.stableID.ambiguityOrdinal = 1
        var draft = LayoutEditing.seed(from: [left, right])
        draft[1].origin = CGPoint(x: 0, y: 1080)

        #expect(Set(draft.map(\.id)).count == 2)
        let profile = LayoutEditing.profile(from: draft, base: [left, right], fingerprint: "fp")
        #expect(profile.displays.map(\.originY) == [0, 1080])
        #expect(profile.displays.map(\.stableID.ambiguityOrdinal) == [0, 1])
    }

    // MARK: - Rotation

    @Test func quarterTurnSwapsModeAndKeepsDisplayAttached() {
        let left = display(uuid: "left", origin: CGPoint(x: -1920, y: 0))
        let main = display(uuid: "main", isMain: true)

        let rotated = LayoutEditing.rotating([left, main], snapshotKey: left.stableID.snapshotKey, to: 90)

        #expect(rotated[0].rotation == 90)
        #expect(rotated[0].mode.width == 1080)
        #expect(rotated[0].mode.height == 1920)
        #expect(rotated[1].originX - rotated[0].originX == 1080)
        #expect(rotated[1].originY == rotated[0].originY)
        #expect(rotated[1].mode == main.mode)
    }

    @Test func quarterTurnBetweenTwoDisplaysKeepsBothAttached() {
        let left = display(uuid: "left", origin: CGPoint(x: -1920, y: 0))
        let main = display(uuid: "main", isMain: true)
        let right = display(uuid: "right", origin: CGPoint(x: 1920, y: 0))

        let rotated = LayoutEditing.rotating([left, main, right], snapshotKey: main.stableID.snapshotKey, to: 90)

        #expect(rotated.map(\.originX) == [-1920, 0, 1080])
        #expect(LayoutEditing.isConnected(LayoutEditing.seed(from: rotated).map(\.frame)))
    }

    @Test func quarterTurnBackRestoresLandscapeMode() {
        let portrait = display(uuid: "left", size: CGSize(width: 1080, height: 1920), rotation: 90)

        let rotated = LayoutEditing.rotating([portrait], snapshotKey: portrait.stableID.snapshotKey, to: 0)

        #expect(rotated[0].rotation == 0)
        #expect(rotated[0].mode.width == 1920)
        #expect(rotated[0].mode.height == 1080)
    }

    @Test func halfTurnKeepsModeAndOrigin() {
        let left = display(uuid: "left", origin: CGPoint(x: -1920, y: 0))
        let main = display(uuid: "main", isMain: true)

        let rotated = LayoutEditing.rotating([left, main], snapshotKey: left.stableID.snapshotKey, to: 180)

        var expected = left
        expected.rotation = 180
        #expect(rotated == [expected, main])
    }

    @Test func stableIdentityUsesUUIDBeforeEDIDFallback() {
        let identified = StableDisplayID(
            uuid: "uuid", vendor: 1, model: 2, serial: 3, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0)
        let fallback = StableDisplayID(
            uuid: nil, vendor: 1, model: 2, serial: 3, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0)

        #expect(identified.identityKey == "uuid")
        #expect(fallback.identityKey == "1:2:3:false")
    }
}
