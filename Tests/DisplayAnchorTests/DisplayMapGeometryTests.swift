import CoreGraphics
import Foundation
import Testing
@testable import DisplayAnchor

struct DisplayMapGeometryTests {

    @Test func emptyFootprintsYieldsIdentityGeometry() {
        let geometry = DisplayMapGeometry(footprints: [], in: CGSize(width: 300, height: 200), padding: 8)
        #expect(geometry.scale == 1.0)
        let sampleRect = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(geometry.rect(for: sampleRect) == sampleRect)
        #expect(geometry.displayLength(50) == 50.0)
    }

    @Test func singleDisplayScalingAndCentering() {
        // 1920x1080 (16:9) placed in a 400x300 view with padding 10
        // Available space: width = 380, height = 280
        // Width fit: 380 / 1920 = 0.1979166667
        // Height fit: 280 / 1080 = 0.2592592593
        // Chosen fit: 380 / 1920 = 19 / 96
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = DisplayMapGeometry(footprints: [display], in: CGSize(width: 400, height: 300), padding: 10)

        let expectedScale: CGFloat = 380.0 / 1920.0
        #expect(abs(geometry.scale - expectedScale) < 0.0001)

        let mapped = geometry.rect(for: display)
        #expect(abs(mapped.width - 380.0) < 0.0001)
        #expect(abs(mapped.height - (1080.0 * expectedScale)) < 0.0001)
        #expect(abs(mapped.minX - 10.0) < 0.0001) // exactly padded horizontally
        // Vertically centered: 10 + (280 - 213.75) / 2 = 43.125
        #expect(abs(mapped.minY - 43.125) < 0.0001)

        // Test displayLength inverse
        #expect(abs(geometry.displayLength(38.0) - (38.0 / expectedScale)) < 0.0001)
    }

    @Test func sideBySideDisplaysPreserveEdgeAdjacency() {
        let leftDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rightDisplay = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let geometry = DisplayMapGeometry(
            footprints: [leftDisplay, rightDisplay],
            in: CGSize(width: 400, height: 200),
            padding: 0
        )

        let mappedLeft = geometry.rect(for: leftDisplay)
        let mappedRight = geometry.rect(for: rightDisplay)

        #expect(abs(mappedLeft.maxX - mappedRight.minX) < 0.0001)
        #expect(abs(mappedLeft.width - mappedRight.width) < 0.0001)
        #expect(abs(mappedLeft.minY - mappedRight.minY) < 0.0001)
        #expect(mappedLeft.minX == 0.0)
        #expect(abs(mappedRight.maxX - 400.0) < 0.0001)
    }

    @Test func stackedDisplaysPreserveVerticalAdjacency() {
        let topDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let bottomDisplay = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let geometry = DisplayMapGeometry(
            footprints: [topDisplay, bottomDisplay],
            in: CGSize(width: 300, height: 400),
            padding: 0
        )

        let mappedTop = geometry.rect(for: topDisplay)
        let mappedBottom = geometry.rect(for: bottomDisplay)

        #expect(abs(mappedTop.maxY - mappedBottom.minY) < 0.0001)
        #expect(abs(mappedTop.height - mappedBottom.height) < 0.0001)
        #expect(abs(mappedTop.minX - mappedBottom.minX) < 0.0001)
    }

    @Test func negativeCoordinatesAreCorrectlyNormalized() {
        // Left display placed at x: -1920, main display at x: 0
        let leftDisplay = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let mainDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = DisplayMapGeometry(
            footprints: [leftDisplay, mainDisplay],
            in: CGSize(width: 400, height: 200),
            padding: 0
        )

        let mappedLeft = geometry.rect(for: leftDisplay)
        let mappedMain = geometry.rect(for: mainDisplay)

        #expect(mappedLeft.minX == 0.0)
        #expect(abs(mappedLeft.maxX - mappedMain.minX) < 0.0001)
        #expect(abs(mappedMain.maxX - 400.0) < 0.0001)
    }

    @Test func portraitAndLandscapeMixedArrangement() {
        // Landscape main: 1920x1080 at (0, 0)
        // Portrait secondary: 1080x1920 at (1920, -420)
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let portrait = CGRect(x: 1920, y: -420, width: 1080, height: 1920)

        let geometry = DisplayMapGeometry(
            footprints: [main, portrait],
            in: CGSize(width: 600, height: 400),
            padding: 10
        )

        let mappedMain = geometry.rect(for: main)
        let mappedPortrait = geometry.rect(for: portrait)

        #expect(abs(mappedMain.maxX - mappedPortrait.minX) < 0.0001)
        #expect(mappedPortrait.height > mappedMain.height)
        #expect(mappedPortrait.minY < mappedMain.minY)
    }
}
