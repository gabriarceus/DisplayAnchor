import Foundation
import Testing
@testable import DisplayAnchor

struct DisplayGeometryTests {

    private func makeDisplay(
        uuid: String?,
        vendor: UInt32 = 1,
        model: UInt32 = 2,
        serial: UInt32 = 3,
        isBuiltin: Bool = false,
        originX: Int = 0,
        originY: Int = 0,
        width: Int = 1920,
        height: Int = 1080,
        pixelWidth: Int = 1920,
        pixelHeight: Int = 1080,
        isMain: Bool = false,
        rotation: Double = 0.0,
        ambiguityOrdinal: Int = 0
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            stableID: StableDisplayID(
                uuid: uuid,
                vendor: vendor,
                model: model,
                serial: serial,
                isBuiltin: isBuiltin,
                unitNumber: 0,
                ambiguityOrdinal: ambiguityOrdinal
            ),
            name: uuid ?? "Display-\(vendor)-\(model)",
            originX: originX,
            originY: originY,
            mode: ModeDescriptor(
                width: width,
                height: height,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                refresh: 60.0,
                ioFlags: 0
            ),
            isMain: isMain,
            mirrorOfUUID: nil,
            rotation: rotation
        )
    }

    // MARK: - Geometry Signature

    @Test func geometrySignatureIsTranslationInvariant() {
        let display1 = makeDisplay(uuid: "d1", originX: 0, originY: 0, isMain: true)
        let display2 = makeDisplay(uuid: "d2", originX: 1920, originY: 0, isMain: false)
        let profileA = LayoutProfile(
            fingerprint: "fp1",
            label: "A",
            savedAt: Date(),
            displays: [display1, display2]
        )

        // Translated coordinate space: entire arrangement shifted by (-500, 300)
        let shifted1 = makeDisplay(uuid: "d1", originX: -500, originY: 300, isMain: true)
        let shifted2 = makeDisplay(uuid: "d2", originX: 1420, originY: 300, isMain: false)
        let profileB = LayoutProfile(
            fingerprint: "fp1",
            label: "B",
            savedAt: Date(),
            displays: [shifted1, shifted2]
        )

        #expect(DisplayEngine.geometrySignature(profileA) == DisplayEngine.geometrySignature(profileB))
    }

    @Test func geometrySignatureIsOrderIndependent() {
        let display1 = makeDisplay(uuid: "d1", originX: 0, originY: 0, isMain: true)
        let display2 = makeDisplay(uuid: "d2", originX: 1920, originY: 0, isMain: false)

        let profileOrder1 = LayoutProfile(
            fingerprint: "fp1",
            label: "Order1",
            savedAt: Date(),
            displays: [display1, display2]
        )
        let profileOrder2 = LayoutProfile(
            fingerprint: "fp1",
            label: "Order2",
            savedAt: Date(),
            displays: [display2, display1]
        )

        #expect(DisplayEngine.geometrySignature(profileOrder1) == DisplayEngine.geometrySignature(profileOrder2))
    }

    @Test func geometrySignatureDetectsMainDisplayChange() {
        let display1Main = makeDisplay(uuid: "d1", originX: 0, originY: 0, isMain: true)
        let display2Side = makeDisplay(uuid: "d2", originX: 1920, originY: 0, isMain: false)
        let profile1 = LayoutProfile(fingerprint: "fp", label: "1", savedAt: Date(), displays: [display1Main, display2Side])

        let display1Side = makeDisplay(uuid: "d1", originX: -1920, originY: 0, isMain: false)
        let display2Main = makeDisplay(uuid: "d2", originX: 0, originY: 0, isMain: true)
        let profile2 = LayoutProfile(fingerprint: "fp", label: "2", savedAt: Date(), displays: [display1Side, display2Main])

        #expect(DisplayEngine.geometrySignature(profile1) != DisplayEngine.geometrySignature(profile2))
    }

    @Test func geometrySignatureDetectsRotationChange() {
        let display1 = makeDisplay(uuid: "d1", originX: 0, originY: 0, isMain: true, rotation: 0)
        let display2Landscape = makeDisplay(uuid: "d2", originX: 1920, originY: 0, isMain: false, rotation: 0)
        let display2Portrait = makeDisplay(uuid: "d2", originX: 1920, originY: 0, isMain: false, rotation: 90)

        let profileLandscape = LayoutProfile(fingerprint: "fp", label: "L", savedAt: Date(), displays: [display1, display2Landscape])
        let profilePortrait = LayoutProfile(fingerprint: "fp", label: "P", savedAt: Date(), displays: [display1, display2Portrait])

        #expect(DisplayEngine.geometrySignature(profileLandscape) != DisplayEngine.geometrySignature(profilePortrait))
    }

    @Test func geometrySignatureDetectsResolutionOrHiDPIChange() {
        let display1 = makeDisplay(uuid: "d1", originX: 0, originY: 0, isMain: true)
        let standardMode = makeDisplay(uuid: "d2", originX: 1920, originY: 0, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080)
        let retinaMode = makeDisplay(uuid: "d2", originX: 1920, originY: 0, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160)

        let profileStandard = LayoutProfile(fingerprint: "fp", label: "Std", savedAt: Date(), displays: [display1, standardMode])
        let profileRetina = LayoutProfile(fingerprint: "fp", label: "Ret", savedAt: Date(), displays: [display1, retinaMode])

        #expect(DisplayEngine.geometrySignature(profileStandard) != DisplayEngine.geometrySignature(profileRetina))
    }

    @Test func geometrySignatureHandlesEmptyDisplays() {
        let emptyProfile = LayoutProfile(fingerprint: "empty", label: "", savedAt: Date(), displays: [])
        #expect(DisplayEngine.geometrySignature(emptyProfile).isEmpty)
    }

    @Test func geometrySignatureFallsBackToFirstDisplayWhenNoMainSpecified() {
        let display1 = makeDisplay(uuid: "d1", originX: 100, originY: 200, isMain: false)
        let display2 = makeDisplay(uuid: "d2", originX: 2020, originY: 200, isMain: false)

        let profile = LayoutProfile(fingerprint: "fp", label: "NoMain", savedAt: Date(), displays: [display1, display2])
        let sig = DisplayEngine.geometrySignature(profile)
        #expect(sig.count == 2)
        #expect(sig.contains { $0.contains("d1|0,0|main:false") })
        #expect(sig.contains { $0.contains("d2|1920,0|main:false") })
    }

    // MARK: - Ambiguous Identity Detection

    @Test func distinctUUIDsAreNotAmbiguousEvenWithSameEDID() {
        let monitor1 = makeDisplay(uuid: "colorsync-uuid-1", vendor: 42, model: 99, serial: 0)
        let monitor2 = makeDisplay(uuid: "colorsync-uuid-2", vendor: 42, model: 99, serial: 0)

        let ambiguous = DisplayEngine.ambiguousIdentityKeys(in: [monitor1, monitor2])
        #expect(ambiguous.isEmpty)
    }

    @Test func matchingEDIDWithoutUUIDsAreIdentifiedAsAmbiguous() {
        let twin1 = makeDisplay(uuid: nil, vendor: 42, model: 99, serial: 0, ambiguityOrdinal: 0)
        let twin2 = makeDisplay(uuid: nil, vendor: 42, model: 99, serial: 0, ambiguityOrdinal: 1)

        let ambiguous = DisplayEngine.ambiguousIdentityKeys(in: [twin1, twin2])
        #expect(ambiguous.count == 1)
        #expect(ambiguous.contains("42:99:0:false"))
    }

    @Test func mixedSetupIdentifiesOnlyTrulyAmbiguousDisplays() {
        let laptop = makeDisplay(uuid: "built-in-uuid", vendor: 1, model: 1, serial: 0, isBuiltin: true, isMain: true)
        let twin1 = makeDisplay(uuid: nil, vendor: 42, model: 99, serial: 0, isBuiltin: false, ambiguityOrdinal: 0)
        let twin2 = makeDisplay(uuid: nil, vendor: 42, model: 99, serial: 0, isBuiltin: false, ambiguityOrdinal: 1)
        let uniqueExternal = makeDisplay(uuid: "dell-uuid", vendor: 55, model: 77, serial: 123)

        let ambiguous = DisplayEngine.ambiguousIdentityKeys(in: [laptop, twin1, twin2, uniqueExternal])
        #expect(ambiguous == Set(["42:99:0:false"]))
    }
}
