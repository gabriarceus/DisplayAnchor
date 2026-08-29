import Foundation
import Testing
@testable import DisplayAnchor

struct LayoutModelsTests {

    @Test func stableDisplayIDEDIDKeyFormat() {
        let id = StableDisplayID(
            uuid: "test-uuid",
            vendor: 1552,
            model: 41234,
            serial: 98765,
            isBuiltin: false,
            unitNumber: 1,
            ambiguityOrdinal: 0
        )
        #expect(id.edidKey == "1552:41234:98765:false")
    }

    @Test func stableDisplayIDIdentityKeyPrefersUUIDOverEDID() {
        let withUUID = StableDisplayID(
            uuid: "colorsync-uuid-1234",
            vendor: 100,
            model: 200,
            serial: 0,
            isBuiltin: false,
            unitNumber: 0,
            ambiguityOrdinal: 0
        )
        #expect(withUUID.identityKey == "colorsync-uuid-1234")

        let withoutUUID = StableDisplayID(
            uuid: nil,
            vendor: 100,
            model: 200,
            serial: 0,
            isBuiltin: true,
            unitNumber: 0,
            ambiguityOrdinal: 0
        )
        #expect(withoutUUID.identityKey == "100:200:0:true")
    }

    @Test func modeDescriptorIsHiDPIComputation() {
        let hiDPI = ModeDescriptor(
            width: 1920,
            height: 1080,
            pixelWidth: 3840,
            pixelHeight: 2160,
            refresh: 60,
            ioFlags: 0
        )
        #expect(hiDPI.isHiDPI)

        let standard = ModeDescriptor(
            width: 1920,
            height: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refresh: 60,
            ioFlags: 0
        )
        #expect(!standard.isHiDPI)

        let scaledDown = ModeDescriptor(
            width: 2560,
            height: 1440,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refresh: 60,
            ioFlags: 0
        )
        #expect(!scaledDown.isHiDPI)
    }

    @Test func layoutModelsCodableRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = DisplaySnapshot(
            stableID: StableDisplayID(
                uuid: "uuid-main",
                vendor: 100,
                model: 200,
                serial: 300,
                isBuiltin: true,
                unitNumber: 0,
                ambiguityOrdinal: 0
            ),
            name: "Built-in Retina Display",
            originX: 0,
            originY: 0,
            mode: ModeDescriptor(
                width: 1728,
                height: 1117,
                pixelWidth: 3456,
                pixelHeight: 2234,
                refresh: 120.0,
                ioFlags: 1234
            ),
            isMain: true,
            mirrorOfUUID: nil,
            rotation: 0.0
        )

        let profile = LayoutProfile(
            fingerprint: "test-fingerprint-abc",
            label: "Desk Setup (2 Displays)",
            savedAt: Date(timeIntervalSince1970: 1700000000),
            displays: [snapshot]
        )

        let document = ProfileDocument(
            version: 1,
            profiles: [profile.fingerprint: profile]
        )

        let encoded = try encoder.encode(document)
        let decoded = try decoder.decode(ProfileDocument.self, from: encoded)

        #expect(decoded.version == 1)
        #expect(decoded.profiles.count == 1)
        let decodedProfile = try #require(decoded.profiles["test-fingerprint-abc"])
        #expect(decodedProfile.fingerprint == "test-fingerprint-abc")
        #expect(decodedProfile.label == "Desk Setup (2 Displays)")
        #expect(decodedProfile.savedAt == Date(timeIntervalSince1970: 1700000000))
        #expect(decodedProfile.displays.count == 1)

        let decodedDisplay = decodedProfile.displays[0]
        #expect(decodedDisplay.name == "Built-in Retina Display")
        #expect(decodedDisplay.isMain)
        #expect(decodedDisplay.originX == 0)
        #expect(decodedDisplay.originY == 0)
        #expect(decodedDisplay.mode.width == 1728)
        #expect(decodedDisplay.mode.pixelWidth == 3456)
        #expect(decodedDisplay.mode.isHiDPI)
        #expect(decodedDisplay.mode.refresh == 120.0)
        #expect(decodedDisplay.stableID.uuid == "uuid-main")
        #expect(decodedDisplay.stableID.isBuiltin)
    }

    @Test func layoutApplyResultEquality() {
        #expect(LayoutApplyResult.applied == LayoutApplyResult.applied)
        #expect(LayoutApplyResult.alreadyMatches == LayoutApplyResult.alreadyMatches)
        #expect(LayoutApplyResult.unmatched == LayoutApplyResult.unmatched)
        #expect(LayoutApplyResult.failed("reason") == LayoutApplyResult.failed("reason"))
        #expect(LayoutApplyResult.failed("reason A") != LayoutApplyResult.failed("reason B"))
        #expect(LayoutApplyResult.applied != LayoutApplyResult.alreadyMatches)
    }
}
