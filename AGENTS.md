# Agent context

DisplayAnchor is a macOS menu bar app for saving and restoring display arrangements.
Use this file as the entry point for project work. Read the relevant documents below
before exploring the source; each topic has one main home.

## Read by task

| Task                                             | Read                                                                     |
| ------------------------------------------------ | ------------------------------------------------------------------------ |
| Any project change                               | [Architecture](docs/architecture.md) and [Contributing](CONTRIBUTING.md) |
| Building, testing, UI, or translations           | [Development](docs/development.md)                                       |
| Installation, settings, or user-visible behavior | [User guide](docs/user-guide.md)                                         |
| Packaging, updates, signing, or publishing       | [Releases](docs/releases.md)                                             |

The architecture guide maps responsibilities to source files and explains the display
flow. The development guide maps tests and describes checks that need a real Mac.

## Project decisions

- Saving a layout is always a user action. Reconnect events and restores must preserve
  the saved layout rather than replace it with the current arrangement.
- Keep the app focused on display configuration. Window placement, accounts, and
  telemetry are outside its scope.
- Preserve the non-sandboxed app and ad-hoc signing baseline. See the architecture
  and release guides for the reasons and update constraints.
- Reuse MenuBarKit for shared panel behavior, UI components, notifications, and
  localization. Check the package before adding a shared helper to this repository.

## Documentation maintenance

Keep README.md as a short introduction with links. Put user instructions in the user
guide, technical concepts and file ownership in architecture, local workflow in
development, and distribution details in releases.

Write project documentation in plain English. Document concepts, constraints, and
source locations; avoid code samples, copied declarations, and command blocks. Read
the linked source for implementation details. When a change affects a documented
concept or moves a file, update its owning document and the relevant links.

Record notable changes under Unreleased in [CHANGELOG.md](CHANGELOG.md). Build and
release files are the source of truth for executable steps. Reading release guidance
does not authorize publishing, pushing, tagging, or accessing signing credentials.
