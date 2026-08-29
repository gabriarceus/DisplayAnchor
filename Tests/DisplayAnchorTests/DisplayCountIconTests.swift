import AppKit
import Foundation
import Testing
@testable import DisplayAnchor

struct DisplayCountIconTests {

    private func makeDisplay(isMain: Bool = false, originX: Int = 0) -> DisplaySnapshot {
        DisplaySnapshot(
            stableID: StableDisplayID(uuid: "d-\(originX)", vendor: 1, model: 1, serial: 1, isBuiltin: false, unitNumber: 0, ambiguityOrdinal: 0),
            name: "Display",
            originX: originX,
            originY: 0,
            mode: ModeDescriptor(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refresh: 60, ioFlags: 0),
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
            makeDisplay(isMain: false, originX: 3840)
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
}
