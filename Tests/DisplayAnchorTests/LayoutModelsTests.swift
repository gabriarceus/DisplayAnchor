import Foundation
import Testing

@testable import DisplayAnchor

/// Saved profiles are keyed by the display-set fingerprint. These tests pin its
/// inputs and output: any change orphans every layout users have saved.
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

    @Test func fingerprintIsPinnedAndOrderIndependent() {
        let expected = "eac8ee4d02c9ddaaca266e8269ea0c7752e29d669bcdd0d07c499b6a4d6aff22"
        #expect(DisplayEngine.fingerprint(edidKeys: ["1:2:3:false", "4:5:6:true"]) == expected)
        #expect(DisplayEngine.fingerprint(edidKeys: ["4:5:6:true", "1:2:3:false"]) == expected)
    }

    @Test func fingerprintCountsDuplicateDisplays() {
        let one = DisplayEngine.fingerprint(edidKeys: ["1:2:3:false"])
        let two = DisplayEngine.fingerprint(edidKeys: ["1:2:3:false", "1:2:3:false"])
        #expect(one != two)
    }
}
