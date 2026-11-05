import AppKit
import Foundation
import Testing

@testable import DisplayAnchor

struct DisplayCountIconTests {

    private func makeDisplay(
        isMain: Bool = false, originX: Int = 0, originY: Int = 0, width: Int = 1920, height: Int = 1080
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            stableID: StableDisplayID(
                uuid: "d-\(originX)", vendor: 1, model: 1, serial: 1, isBuiltin: false, unitNumber: 0,
                ambiguityOrdinal: 0),
            name: "Display",
            originX: originX,
            originY: originY,
            mode: ModeDescriptor(
                width: width, height: height, pixelWidth: width, pixelHeight: height, refresh: 60, ioFlags: 0),
            isMain: isMain,
            mirrorOfUUID: nil,
            rotation: 0
        )
    }

    @Test func rendersTemplateImageForEmptyDisplaysClampedToOne() {
        let image = DisplayCountIcon.image(displays: [], pointSize: 14)
        #expect(image.isTemplate)
        #expect(image.size.height == 14)
        // 1 rect: width = 1 * 6.44 + 0 * 2.24 + 1.12 = 7.56
        #expect(abs(image.size.width - 7.56) < 0.001)
    }

    @Test func rendersTemplateImageForMultipleDisplays() {
        let displays = [
            makeDisplay(isMain: true, originX: 0),
            makeDisplay(isMain: false, originX: 1920),
            makeDisplay(isMain: false, originX: 3840),
        ]
        let image = DisplayCountIcon.image(displays: displays, pointSize: 14)
        #expect(image.isTemplate)
        #expect(image.size.height == 14)
        // 3 rects: width = 3 * 6.44 + 2 * 2.24 + 1.12 = 24.92
        #expect(abs(image.size.width - 24.92) < 0.001)
    }

    @Test func clampsDisplayCountToMaxRects() {
        let displays = (0..<6).map { makeDisplay(isMain: $0 == 0, originX: $0 * 1920) }
        let image = DisplayCountIcon.image(displays: displays, pointSize: 14)
        #expect(image.isTemplate)
        #expect(image.size.height == 14)
        // 4 rects (clamped): width = 4 * 6.44 + 3 * 2.24 + 1.12 = 33.6
        #expect(abs(image.size.width - 33.6) < 0.001)
    }

    @Test func smallerDisplaysDrawSmallerRects() {
        let displays = [
            makeDisplay(originX: 0, width: 960),
            makeDisplay(isMain: true, originX: 960),
        ]
        let image = DisplayCountIcon.image(displays: displays, pointSize: 14)
        // Long sides 1080 and 1920, scales 0.5625 and 1: width = 6.44 * 1.5625 + 2.24 + 1.12 = 13.4225
        #expect(abs(image.size.width - 13.4225) < 0.001)
    }

    @Test func rectsFollowVerticalAlignmentOfDisplays() {
        // A smaller display aligned to the bottom of a larger one, then one aligned to its top.
        let displays = [
            makeDisplay(originX: 0, originY: 320, width: 1792, height: 1120),
            makeDisplay(isMain: true, originX: 1792, width: 2560, height: 1440),
            makeDisplay(originX: 4352, width: 1792, height: 1120),
        ]
        let rects = DisplayCountIcon.glyphRects(displays: displays, pointSize: 14)
        #expect(abs(rects[0].minY - rects[1].minY) < 0.001)
        #expect(abs(rects[2].maxY - rects[1].maxY) < 0.001)
    }
}
