import CoreGraphics
import Foundation

/// Stable, replug-surviving identity for a single physical display.
///
/// `uuid` (from ColorSync) survives most reconnects; the vendor/model/serial
/// triple is the EDID-stable fallback used to match displays and to build the
/// display-set fingerprint. `ambiguityOrdinal` disambiguates two displays that
/// share the same EDID (identical model, equal/zero serial) by a port-order
/// heuristic — a fundamentally best-effort tiebreak.
struct StableDisplayID: Codable, Equatable, Sendable {
    var uuid: String?
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    var isBuiltin: Bool
    var unitNumber: UInt32
    var ambiguityOrdinal: Int

    /// EDID-stable key used for the display-set fingerprint.
    var edidKey: String { "\(vendor):\(model):\(serial):\(isBuiltin)" }

    /// Best available per-physical-display identity. The ColorSync UUID is derived
    /// from the full EDID and differs even between same-model units (whose numeric
    /// serial is often 0), so it distinguishes "identical" monitors when present.
    var identityKey: String { uuid ?? edidKey }
}

/// Serializable description of a display mode, re-resolved against the live
/// mode list on restore (a raw `CGDisplayMode` reference is not persistable).
struct ModeDescriptor: Codable, Equatable, Sendable {
    var width: Int          // logical points ("looks like" resolution)
    var height: Int
    var pixelWidth: Int     // backing pixels; HiDPI when greater than `width`
    var pixelHeight: Int
    var refresh: Double     // Hz; 0 means unspecified
    var ioFlags: UInt32

    var isHiDPI: Bool { pixelWidth > width }
}

/// One display within a captured layout: its identity, position, mode, and role.
struct DisplaySnapshot: Codable, Equatable, Sendable {
    var stableID: StableDisplayID
    var name: String
    var originX: Int        // global top-left coordinate space
    var originY: Int
    var mode: ModeDescriptor
    var isMain: Bool
    var mirrorOfUUID: String?
    var rotation: Double
}

/// A saved arrangement for one physical set of displays, keyed by `fingerprint`.
struct LayoutProfile: Codable, Equatable, Sendable {
    var fingerprint: String
    var label: String
    var savedAt: Date
    var displays: [DisplaySnapshot]
}

/// Result of attempting to apply a layout.
enum LayoutApplyResult: Equatable, Sendable {
    case applied
    case alreadyMatches
    case unmatched          // saved displays could not be mapped to the live set
    case failed(String)
}
