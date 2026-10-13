# DisplayAnchor

A small macOS menu bar app that remembers and restores your display arrangement
when you reconnect external monitors or a dock. It restores relative positions,
the main display, resolution, and rotation.

- Save a preferred layout for each set of connected displays.
- Restore it on demand or enable automatic restore after reconnect.
- Rearrange displays in a visual editor and change the main display or rotation.

Layouts are saved manually and stored locally. No accounts, telemetry, or window
management. Display operations need no Accessibility or Screen Recording access.
Optional in-app updates use Sparkle.

<p align="center">
  <img src="docs/screenshots/panel.png" alt="DisplayAnchor panel with a display map and saved layouts" width="360">
</p>

Requires **macOS 26 or later**. Releases support **Apple Silicon and Intel**. The app
is ad-hoc signed; a downloaded copy needs first-launch approval in Privacy & Security.

[Download the latest release](https://github.com/gabriarceus/DisplayAnchor/releases/latest)
· [Installation and user guide](docs/user-guide.md)

## Documentation

- [Development](docs/development.md) — building, testing, and translations
- [Architecture](docs/architecture.md) — source map and display behavior
- [Releases](docs/releases.md) — packaging, signing, and updates
- [Contributing and support](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)
- [Agent context](AGENTS.md) — starting point for AI agents

[MIT License](LICENSE) © 2026 Gabriarceus
