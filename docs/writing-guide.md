# Writing guide

These rules apply to code comments, project documentation, the changelog, and commit messages. Write in plain English: short sentences, common words, few negations. Keep the precise technical term when it is the right word.

## Where information goes

Each kind of information has one home. Put it there and nowhere else.

| Information                                                        | Home                                              |
| ------------------------------------------------------------------ | ------------------------------------------------- |
| What a symbol is and does, what nil means, side effects, ownership | Doc comment (`///`) on the symbol                 |
| Why non-obvious code has its shape                                 | Inline comment (`//`) next to that code           |
| Concepts, constraints, and file ownership                          | The owning document in docs/, listed in AGENTS.md |
| What changed for users of a release                                | CHANGELOG.md                                      |
| Why a change was made, alternatives, history, ticket context       | Commit message or pull request                    |
| Instructions for AI agents                                         | AGENTS.md only                                    |

## Doc comments

- State the contract: what the symbol is and does. Add what nil means, when it fails, side effects, and what would surprise a caller. Use one line unless the behavior needs more.
- Do not explain why the symbol exists, who calls it, or how it was fixed. Phrases such as "so that", "in order to", "used by", "called from", "now", "no longer", and "previously" usually mark text that belongs in a commit.
- Refer to symbols with backticks, such as `status` or `performApplying(_:)`. Square brackets are not Swift documentation syntax.
- Put the doc comment directly on the declaration it describes. An overview of a whole file uses `//` comments at the top.
- When behavior changes, update its doc comment in the same change. Keep the comments of code you did not change.

## Inline comments

- Write one only when the reason is not visible in the code: a platform quirk, an ordering constraint, a unit, a piece of math, or a workaround. "Re-setting the current origin can hang the call; skip no-ops" is a good example.
- Do not restate what the code does.
- Do not write "keep in sync with X". Remove the duplication instead, with one owner or a shared constant. When the other side is outside the repository (Info.plist keys, the release workflow, a system API), a short comment that names it is fine.

## Project documentation

- Each topic has one owning document. README.md is a short introduction with links. User instructions go in the user guide, technical concepts and file ownership in architecture, local workflow in development, distribution in releases, and conventions in the Swift style guide and this guide. Link to the owner instead of repeating it.
- Document concepts, constraints, and source locations. Avoid code samples, copied declarations, and command blocks; the source and the scripts are the truth for details.
- Write only lasting facts. No notes about temporary state ("this screenshot is outdated", "not configured yet"), no test-session results, no TODO lists. Fix the cause, or open an issue.
- When a change affects a documented concept or moves a file, update the owning document and its links in the same change.
- In Markdown, write one line per paragraph or list item. Do not wrap prose by hand.

## Changelog

CHANGELOG.md follows Keep a Changelog. Its sections become the release notes in the in-app update window, so users read it.

- Add entries under Unreleased only. A released section changes only to fix a mistake.
- Use the categories Added, Changed, Fixed, Maintenance, and Removed, in this order, and only those a release needs. Keep entries in alphabetical order within a category.
- Write Added, Changed, Fixed, and Removed for users: what they will notice, in the words the app uses. No file names, tools, or internal terms.
- Put changes users do not notice under Maintenance: build and release tooling, tests, documentation, and dependency updates. Maintenance stays in the file but is left out of the update window.
- One change gets one entry. Small fixes for the same change share that entry.

## Commit messages and pull requests

- Write a short imperative summary line, then the reason for the change and anything a reviewer must check by hand.
- The design rationale, the alternatives that were rejected, and the history of a fix go here, not into code comments.
