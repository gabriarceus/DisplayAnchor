import os

/// Centralized unified-logging entry points, grouped by subsystem area.
///
/// View live:
///   log stream --predicate 'subsystem == "io.github.gabriarceus.DisplayAnchor"' --level debug --style compact
/// View recent history:
///   log show --predicate 'subsystem == "io.github.gabriarceus.DisplayAnchor"' --last 10m --style compact
enum Log {
    private static let subsystem = "io.github.gabriarceus.DisplayAnchor"

    /// Save/restore policy decisions and their outcomes.
    static let restore = Logger(subsystem: subsystem, category: "restore")
    /// CoreGraphics layout resolution and application steps.
    static let engine = Logger(subsystem: subsystem, category: "engine")
    /// Display-reconfiguration events and debounce.
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    /// Status item and popover presentation.
    static let ui = Logger(subsystem: subsystem, category: "ui")
    /// Update feed checks and installation.
    static let updates = Logger(subsystem: subsystem, category: "updates")
    /// Reading, validating, and writing saved layout profiles.
    static let profiles = Logger(subsystem: subsystem, category: "profiles")
}
