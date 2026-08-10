import AppKit
import ColorSync
import CoreGraphics
import CryptoKit
import Foundation
import IOKit
import os

/// Pure CoreGraphics/ColorSync wrapper that reads the current display
/// arrangement, applies a saved one, and computes the display-set fingerprint.
/// Stateless: every entry point reads live data. Functions that resolve display
/// names touch `NSScreen` and are therefore main-actor isolated.
enum DisplayEngine {

    // MARK: - Enumeration

    /// Active (connected, awake, drawable) displays. The first is the main one.
    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    // MARK: - Identity

    static func uuidString(for id: CGDirectDisplayID) -> String? {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = unmanaged.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String?
    }

    static func stableID(for id: CGDirectDisplayID, ambiguityOrdinal: Int) -> StableDisplayID {
        StableDisplayID(
            uuid: uuidString(for: id),
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id),
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            unitNumber: CGDisplayUnitNumber(id),
            ambiguityOrdinal: ambiguityOrdinal
        )
    }

    /// EDID-stable key for a live display (matches `StableDisplayID.edidKey`).
    private static func edidKey(_ id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(CGDisplaySerialNumber(id)):\(CGDisplayIsBuiltin(id) != 0)"
    }

    /// Assigns a stable ordinal within each identical-EDID group (port order,
    /// then current position). Displays with a unique EDID get ordinal 0.
    static func ambiguityOrdinals(for ids: [CGDirectDisplayID]) -> [CGDirectDisplayID: Int] {
        var groups: [String: [CGDirectDisplayID]] = [:]
        for id in ids { groups[edidKey(id), default: []].append(id) }

        var result: [CGDirectDisplayID: Int] = [:]
        for (_, members) in groups {
            if members.count <= 1 {
                members.forEach { result[$0] = 0 }
                continue
            }
            let sorted = members.sorted { a, b in
                let ua = CGDisplayUnitNumber(a), ub = CGDisplayUnitNumber(b)
                if ua != ub { return ua < ub }
                let oa = CGDisplayBounds(a).origin, ob = CGDisplayBounds(b).origin
                return (oa.x, oa.y) < (ob.x, ob.y)
            }
            for (index, id) in sorted.enumerated() { result[id] = index }
        }
        return result
    }

    // MARK: - Fingerprint

    /// Order-independent hash over the EDID-stable identity of a set of displays.
    static func fingerprint(for ids: [CGDirectDisplayID]) -> String {
        let joined = ids.map(edidKey).sorted().joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", Int($0)) }.joined()
    }

    static func currentFingerprint() -> String {
        fingerprint(for: activeDisplayIDs())
    }

    // MARK: - Snapshot

    @MainActor
    static func snapshotCurrentLayout(label: String = "", savedAt: Date = Date()) -> LayoutProfile {
        let ids = activeDisplayIDs()
        let ordinals = ambiguityOrdinals(for: ids)
        let displays: [DisplaySnapshot] = ids.map { id in
            let bounds = CGDisplayBounds(id)
            let descriptor = CGDisplayCopyDisplayMode(id).map(modeDescriptor) ?? ModeDescriptor(
                width: Int(bounds.width), height: Int(bounds.height),
                pixelWidth: Int(bounds.width), pixelHeight: Int(bounds.height),
                refresh: 0, ioFlags: 0
            )
            let mirrorMaster = CGDisplayMirrorsDisplay(id)
            return DisplaySnapshot(
                stableID: stableID(for: id, ambiguityOrdinal: ordinals[id] ?? 0),
                name: displayName(for: id),
                originX: Int(bounds.origin.x.rounded()),
                originY: Int(bounds.origin.y.rounded()),
                mode: descriptor,
                isMain: CGDisplayIsMain(id) != 0,
                mirrorOfUUID: mirrorMaster != kCGNullDirectDisplay ? uuidString(for: mirrorMaster) : nil,
                rotation: CGDisplayRotation(id)
            )
        }
        return LayoutProfile(
            fingerprint: fingerprint(for: ids),
            label: label,
            savedAt: savedAt,
            displays: displays
        )
    }

    private static func modeDescriptor(_ mode: CGDisplayMode) -> ModeDescriptor {
        ModeDescriptor(
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refresh: mode.refreshRate,
            ioFlags: mode.ioFlags
        )
    }

    @MainActor
    static func displayName(for id: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(id) != 0 { return "Built-in Display" }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[key] as? NSNumber, number.uint32Value == id {
                return screen.localizedName
            }
        }
        return "Display \(id)"
    }

    // MARK: - Geometry comparison

    /// Order-independent geometric signature of a layout, normalized so the main
    /// display sits at the origin. Two layouts with equal signatures are visually
    /// identical (same relative positions, main display, resolutions, and
    /// rotations). Keyed by each display's stable identity (ColorSync UUID when
    /// available, EDID otherwise) so it survives reconnects and unit-number
    /// reassignment.
    static func geometrySignature(_ profile: LayoutProfile) -> [String] {
        guard let main = profile.displays.first(where: { $0.isMain }) ?? profile.displays.first else { return [] }
        return profile.displays.map { d in
            let relX = d.originX - main.originX
            let relY = d.originY - main.originY
            return "\(d.stableID.identityKey)|\(relX),\(relY)|main:\(d.isMain)|\(d.mode.width)x\(d.mode.height)@\(d.mode.pixelWidth)x\(d.mode.pixelHeight)|rot:\(Int(d.rotation.rounded()))"
        }.sorted()
    }

    @MainActor
    static func currentMatches(_ profile: LayoutProfile) -> Bool {
        geometrySignature(snapshotCurrentLayout()) == geometrySignature(profile)
    }

    // MARK: - Apply

    @MainActor
    static func applyLayout(_ profile: LayoutProfile) async -> LayoutApplyResult {
        let liveIDs = activeDisplayIDs()
        Log.engine.debug("applyLayout: '\(profile.label, privacy: .public)' fp=\(profile.fingerprint, privacy: .public) saved=\(profile.displays.count) live=\(liveIDs.count)")
        let liveOrdinals = ambiguityOrdinals(for: liveIDs)
        for id in liveIDs {
            let o = CGDisplayBounds(id).origin
            Log.engine.debug("live id=\(id) uuid=\(uuidString(for: id) ?? "—", privacy: .public) unit=\(CGDisplayUnitNumber(id)) ord=\(liveOrdinals[id] ?? -1) edid=\(edidKey(id), privacy: .public) main=\(CGDisplayIsMain(id) != 0) origin=(\(Int(o.x)),\(Int(o.y)))")
        }
        guard !liveIDs.isEmpty else {
            Log.engine.notice("applyLayout: no live displays → unmatched")
            return .unmatched
        }
        guard let matched = resolve(profile: profile, liveIDs: liveIDs) else {
            Log.engine.notice("applyLayout: could not map saved displays to live set → unmatched")
            return .unmatched
        }
        if currentMatches(profile) {
            Log.engine.notice("applyLayout: live layout already matches saved → alreadyMatches")
            return .alreadyMatches
        }

        // 0. Rotation first, outside the configuration transaction (it goes through
        // the IOKit framebuffer transform, not CoreGraphics). The transform resets
        // the display mode, so modes/origins are configured only after it settles.
        // Best-effort: a rejected rotation still lets geometry apply.
        var rotationPending = false
        for entry in matched {
            let target = Int(entry.snapshot.rotation.rounded())
            guard Int(CGDisplayRotation(entry.id).rounded()) != target else { continue }
            Log.engine.debug("applyLayout: rotate '\(entry.snapshot.name, privacy: .public)' → \(target)°")
            if setRotation(entry.id, degrees: target) { rotationPending = true }
        }
        if rotationPending {
            try? await Task.sleep(for: .seconds(2))
        }

        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let config = configRef else {
            Log.engine.error("applyLayout: CGBeginDisplayConfiguration failed → failed")
            return .failed("CGBeginDisplayConfiguration failed")
        }

        func cancel(_ message: String) -> LayoutApplyResult {
            CGCancelDisplayConfiguration(config)
            Log.engine.error("applyLayout: \(message, privacy: .public) → failed (config cancelled)")
            return .failed(message)
        }

        let uuidToLive: [String: CGDirectDisplayID] = Dictionary(
            matched.compactMap { entry in entry.snapshot.stableID.uuid.map { ($0, entry.id) } },
            uniquingKeysWith: { first, _ in first }
        )

        // 1. Mirroring first: changing a mode/origin can break mirror sets.
        for entry in matched {
            let master = entry.snapshot.mirrorOfUUID.flatMap { uuidToLive[$0] } ?? kCGNullDirectDisplay
            if CGConfigureDisplayMirrorOfDisplay(config, entry.id, master) != .success {
                return cancel("CGConfigureDisplayMirrorOfDisplay failed")
            }
        }

        // 2. Modes (skip mirrored slaves — their mode follows the master).
        for entry in matched where entry.snapshot.mirrorOfUUID == nil {
            if let mode = bestMode(for: entry.id, descriptor: entry.snapshot.mode),
               CGConfigureDisplayWithDisplayMode(config, entry.id, mode, nil) != .success {
                return cancel("CGConfigureDisplayWithDisplayMode failed")
            }
        }

        // 3. Origins last, translated so the saved main display lands at (0,0).
        guard let main = profile.displays.first(where: { $0.isMain }) ?? profile.displays.first else {
            return cancel("no main display in profile")
        }
        for entry in matched where entry.snapshot.mirrorOfUUID == nil {
            let targetX = Int32(entry.snapshot.originX - main.originX)
            let targetY = Int32(entry.snapshot.originY - main.originY)
            let current = CGDisplayBounds(entry.id).origin
            // Re-setting the current origin can hang the call for seconds; skip no-ops.
            if Int32(current.x.rounded()) != targetX || Int32(current.y.rounded()) != targetY {
                Log.engine.debug("applyLayout: move '\(entry.snapshot.name, privacy: .public)' (\(Int(current.x)),\(Int(current.y))) → (\(targetX),\(targetY))")
                if CGConfigureDisplayOrigin(config, entry.id, targetX, targetY) != .success {
                    return cancel("CGConfigureDisplayOrigin failed")
                }
            } else {
                Log.engine.debug("applyLayout: '\(entry.snapshot.name, privacy: .public)' already at (\(targetX),\(targetY)) — skip")
            }
        }

        let error = CGCompleteDisplayConfiguration(config, .permanently)
        if error == .success {
            Log.engine.notice("applyLayout: applied '\(profile.label, privacy: .public)'")
            return .applied
        }
        Log.engine.error("applyLayout: CGCompleteDisplayConfiguration error \(error.rawValue) → failed")
        return .failed("CGCompleteDisplayConfiguration error \(error.rawValue)")
    }

    private struct MatchedDisplay { let snapshot: DisplaySnapshot; let id: CGDirectDisplayID }

    /// Maps every saved display to a distinct live display (UUID → EDID → ordinal).
    /// Returns nil if any saved display cannot be matched.
    private static func resolve(profile: LayoutProfile, liveIDs: [CGDirectDisplayID]) -> [MatchedDisplay]? {
        let ordinals = ambiguityOrdinals(for: liveIDs)
        var remaining = liveIDs
        var matched: [MatchedDisplay] = []

        for snapshot in profile.displays {
            // 1. Exact UUID match.
            if let uuid = snapshot.stableID.uuid,
               let index = remaining.firstIndex(where: { uuidString(for: $0) == uuid }) {
                Log.engine.debug("resolve: saved '\(snapshot.name, privacy: .public)' (ord \(snapshot.stableID.ambiguityOrdinal)) → live id=\(remaining[index]) unit=\(CGDisplayUnitNumber(remaining[index])) via UUID")
                matched.append(MatchedDisplay(snapshot: snapshot, id: remaining[index]))
                remaining.remove(at: index)
                continue
            }
            // 2. EDID match (vendor/model/serial/builtin).
            let candidateIndices = remaining.indices.filter { index in
                let id = remaining[index]
                return CGDisplayVendorNumber(id) == snapshot.stableID.vendor
                    && CGDisplayModelNumber(id) == snapshot.stableID.model
                    && CGDisplaySerialNumber(id) == snapshot.stableID.serial
                    && (CGDisplayIsBuiltin(id) != 0) == snapshot.stableID.isBuiltin
            }
            guard !candidateIndices.isEmpty else {
                Log.engine.notice("resolve: no live display matches saved '\(snapshot.name, privacy: .public)' edid=\(snapshot.stableID.edidKey, privacy: .public)")
                return nil
            }
            if candidateIndices.count == 1 {
                let index = candidateIndices[0]
                Log.engine.debug("resolve: saved '\(snapshot.name, privacy: .public)' → live id=\(remaining[index]) via EDID (unique)")
                matched.append(MatchedDisplay(snapshot: snapshot, id: remaining[index]))
                remaining.remove(at: index)
                continue
            }
            // 3. Ambiguous group: prefer the matching ordinal, else the first candidate.
            let chosen = candidateIndices.first { (ordinals[remaining[$0]] ?? 0) == snapshot.stableID.ambiguityOrdinal }
                ?? candidateIndices[0]
            Log.engine.notice("resolve: saved '\(snapshot.name, privacy: .public)' AMBIGUOUS (ord \(snapshot.stableID.ambiguityOrdinal)) → live id=\(remaining[chosen]) unit=\(CGDisplayUnitNumber(remaining[chosen])) ord=\(ordinals[remaining[chosen]] ?? -1) via ORDINAL")
            matched.append(MatchedDisplay(snapshot: snapshot, id: remaining[chosen]))
            remaining.remove(at: chosen)
        }
        return matched
    }

    /// Best live mode for a saved descriptor: exact point+pixel match first (in
    /// either orientation — a quarter-turned display reports swapped dimensions),
    /// then closest refresh, then matching IO flags, then closest point size.
    private static func bestMode(for id: CGDirectDisplayID, descriptor: ModeDescriptor) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode], !modes.isEmpty else {
            return CGDisplayCopyDisplayMode(id)
        }
        let exact = modes.filter {
            ($0.width == descriptor.width && $0.height == descriptor.height
                && $0.pixelWidth == descriptor.pixelWidth && $0.pixelHeight == descriptor.pixelHeight)
                || ($0.width == descriptor.height && $0.height == descriptor.width
                    && $0.pixelWidth == descriptor.pixelHeight && $0.pixelHeight == descriptor.pixelWidth)
        }
        let pool = exact.isEmpty ? modes : exact
        return pool.min { a, b in
            let da = abs(a.refreshRate - descriptor.refresh), db = abs(b.refreshRate - descriptor.refresh)
            if da != db { return da < db }
            let fa = a.ioFlags == descriptor.ioFlags ? 0 : 1, fb = b.ioFlags == descriptor.ioFlags ? 0 : 1
            if fa != fb { return fa < fb }
            let sa = abs(a.width - descriptor.width) + abs(a.height - descriptor.height)
            let sb = abs(b.width - descriptor.width) + abs(b.height - descriptor.height)
            return sa < sb
        }
    }

    // MARK: - Live edits

    /// The live display ID currently matching `snapshot`, using the same
    /// UUID → EDID → ordinal strategy as `resolve`. Nil if none matches.
    static func liveID(for snapshot: DisplaySnapshot) -> CGDirectDisplayID? {
        let liveIDs = activeDisplayIDs()
        if let uuid = snapshot.stableID.uuid,
           let id = liveIDs.first(where: { uuidString(for: $0) == uuid }) {
            return id
        }
        let ordinals = ambiguityOrdinals(for: liveIDs)
        let candidates = liveIDs.filter { id in
            CGDisplayVendorNumber(id) == snapshot.stableID.vendor
                && CGDisplayModelNumber(id) == snapshot.stableID.model
                && CGDisplaySerialNumber(id) == snapshot.stableID.serial
                && (CGDisplayIsBuiltin(id) != 0) == snapshot.stableID.isBuiltin
        }
        if candidates.count == 1 { return candidates[0] }
        return candidates.first { (ordinals[$0] ?? 0) == snapshot.stableID.ambiguityOrdinal } ?? candidates.first
    }

    /// Applies the best live match for `descriptor` to a single display. Returns
    /// `.alreadyMatches` (changing nothing) when the current mode already fits.
    @MainActor
    static func setMode(_ id: CGDirectDisplayID, to descriptor: ModeDescriptor) -> LayoutApplyResult {
        guard let mode = bestMode(for: id, descriptor: descriptor) else {
            return .failed("no display mode available")
        }
        if let current = CGDisplayCopyDisplayMode(id),
           current.width == mode.width, current.height == mode.height,
           current.pixelWidth == mode.pixelWidth, current.pixelHeight == mode.pixelHeight,
           current.refreshRate == mode.refreshRate {
            return .alreadyMatches
        }
        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let config = configRef else {
            return .failed("CGBeginDisplayConfiguration failed")
        }
        guard CGConfigureDisplayWithDisplayMode(config, id, mode, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            Log.engine.error("setMode: CGConfigureDisplayWithDisplayMode failed for display \(id)")
            return .failed("CGConfigureDisplayWithDisplayMode failed")
        }
        let error = CGCompleteDisplayConfiguration(config, .permanently)
        if error == .success {
            Log.engine.notice("setMode: display \(id) → \(mode.width)x\(mode.height)")
            return .applied
        }
        return .failed("CGCompleteDisplayConfiguration error \(error.rawValue)")
    }

    /// Sets a display's rotation to `degrees` (0/90/180/270). CoreGraphics exposes
    /// rotation read-only, so this uses the IOKit framebuffer transform request —
    /// the only available write path. Best-effort: returns false (and changes
    /// nothing) if the framebuffer service can't be reached or rejects the probe.
    static func setRotation(_ id: CGDirectDisplayID, degrees: Int) -> Bool {
        // IOGraphicsTypes.h scale flags: swapAxes = 1, invertX = 2, invertY = 4;
        // the kIOScaleRotate* transforms are their combinations (as in fb-rotate).
        let transforms: [Int: UInt32] = [0: 0x0, 90: 0x3, 180: 0x6, 270: 0x5]
        guard let transform = transforms[((degrees % 360) + 360) % 360] else {
            Log.engine.error("setRotation: unsupported angle \(degrees)°")
            return false
        }
        let display = ioService(for: id)
        guard display != 0 else {
            Log.engine.error("setRotation: no IOService for display \(id)")
            return false
        }
        // The transform request must go to the IOFramebuffer ancestor: probing the
        // IODisplayConnect node itself returns kIOReturnUnsupported.
        let service = framebufferService(from: display)
        IOObjectRelease(display)
        guard service != 0 else {
            Log.engine.error("setRotation: no IOFramebuffer ancestor for display \(id)")
            return false
        }
        defer { IOObjectRelease(service) }
        // 0x400 = kIOFBSetTransform; the transform flags sit in the upper 16 bits.
        let options: UInt32 = 0x00000400 | (transform << 16)
        let result = IOServiceRequestProbe(service, options)
        if result != KERN_SUCCESS {
            Log.engine.error("setRotation: IOServiceRequestProbe failed (\(result)) for display \(id)")
            return false
        }
        Log.engine.notice("setRotation: display \(id) → \(degrees)°")
        return true
    }

    /// Nearest ancestor of `display` (inclusive) in the service plane that is an
    /// `IOFramebuffer`. The caller owns the returned service and must
    /// `IOObjectRelease` it; returns 0 if none is found. `display` is untouched.
    private static func framebufferService(from display: io_service_t) -> io_service_t {
        var current = display
        IOObjectRetain(current)
        while current != 0 {
            if IOObjectConformsTo(current, "IOFramebuffer") != 0 { return current }
            var parent = io_registry_entry_t()
            let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            current = result == KERN_SUCCESS ? parent : 0
        }
        return 0
    }

    /// Resolves the `IODisplayConnect` node backing a display by matching its
    /// vendor/product against the display's EDID numbers (the replacement for the
    /// removed `CGDisplayIOServicePort`). The caller owns the returned service and
    /// must `IOObjectRelease` it; returns 0 if not found. Identical twin displays
    /// resolve to the first match — a best-effort tiebreak.
    private static func ioService(for id: CGDirectDisplayID) -> io_service_t {
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?
                .takeRetainedValue() as? [String: Any],
               (info["DisplayVendorID"] as? NSNumber)?.uint32Value == vendor,
               (info["DisplayProductID"] as? NSNumber)?.uint32Value == model {
                return service
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return 0
    }

    // MARK: - Diagnostics

    /// Identity keys shared by more than one connected display — i.e. displays that
    /// are genuinely indistinguishable (same UUID, or no UUID and same EDID). Two
    /// same-model monitors with distinct ColorSync UUIDs are NOT flagged.
    static func ambiguousIdentityKeys(in displays: [DisplaySnapshot]) -> Set<String> {
        let counts = Dictionary(grouping: displays, by: { $0.stableID.identityKey }).mapValues(\.count)
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    @MainActor
    static func diagnosticsText() -> String {
        let profile = snapshotCurrentLayout()
        let ambiguous = ambiguousIdentityKeys(in: profile.displays)
        var lines: [String] = [
            "DisplayAnchor — diagnostics",
            "Fingerprint: \(profile.fingerprint)",
            "Displays: \(profile.displays.count)",
        ]
        for d in profile.displays {
            lines.append("")
            lines.append("• \(d.name)\(d.isMain ? " [MAIN]" : "")")
            let hz = d.mode.refresh > 0 ? "\(Int(d.mode.refresh.rounded()))Hz" : "—"
            lines.append("  origin (\(d.originX), \(d.originY)) · \(d.mode.width)x\(d.mode.height) pt · \(d.mode.pixelWidth)x\(d.mode.pixelHeight) px\(d.mode.isHiDPI ? " (HiDPI)" : "") · \(hz) · rot \(Int(d.rotation))°")
            lines.append("  vendor \(d.stableID.vendor) · model \(d.stableID.model) · serial \(d.stableID.serial) · unit \(d.stableID.unitNumber)")
            lines.append("  uuid \(d.stableID.uuid ?? "—")")
            if ambiguous.contains(d.stableID.identityKey) {
                lines.append("  ⚠️ indistinguishable from another connected display (ordinal \(d.stableID.ambiguityOrdinal))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
