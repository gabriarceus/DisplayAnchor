# Agent context

DisplayAnchor is a macOS menu bar app for saving and restoring display arrangements. Use this file as the entry point for project work. Read the relevant documents below before exploring the source; each topic has one main home.

## Read by task

| Task                                                   | Read                                                                     |
| ------------------------------------------------------ | ------------------------------------------------------------------------ |
| Any project change                                     | [Architecture](docs/architecture.md) and [Contributing](CONTRIBUTING.md) |
| Writing or reviewing Swift code                        | [Swift style](docs/swift-style.md)                                       |
| Writing comments, documentation, changelog, or commits | [Writing guide](docs/writing-guide.md)                                   |
| Building, testing, UI, or translations                 | [Development](docs/development.md)                                       |
| Installation, settings, or user-visible behavior       | [User guide](docs/user-guide.md)                                         |
| Packaging, updates, signing, or publishing             | [Releases](docs/releases.md)                                             |

Most tasks match more than one row: a code change usually needs Architecture, Swift style, and the Writing guide. The architecture guide maps responsibilities to source files and explains the display flow. The development guide maps tests and describes checks that need a real Mac.

## Project decisions

- Saving a layout is always a user action. Reconnect events and restores must preserve the saved layout rather than replace it with the current arrangement.
- Keep the app focused on display configuration. Window placement, accounts, and telemetry are outside its scope.
- Preserve the non-sandboxed app and ad-hoc signing baseline. See the architecture and release guides for the reasons and update constraints.
- Reuse MenuBarKit for shared panel behavior, UI components, notifications, and localization. Check the package before adding a shared helper to this repository.

## Boundaries

- Build and release files are the source of truth for executable steps. Reading release guidance does not authorize publishing, pushing, tagging, or accessing signing credentials.
- Never inspect or presence-check signing keys or other credentials.
- Without a Mac and real displays, source inspection is not a runtime test. Say which checks remain unrun.

## Before you finish

- Run `swift test`. Run the Python release-tool tests when you change scripts/.
- Format the Swift files you changed with `swift format -i`, and check that `swift format lint --recursive --strict Package.swift Sources Tests` is clean.
- Read every comment you added or changed against the [Writing guide](docs/writing-guide.md): a contract or a reason, no history.
- Update the owning document when a documented concept, setting, or file changes.
- Add one entry under Unreleased in [CHANGELOG.md](CHANGELOG.md), written for users, or under Maintenance when users do not notice the change.
- Leave no temporary notes, debug output, or test artifacts in code or documentation.
- List the manual hardware checks that the change needs and that you did not run.
