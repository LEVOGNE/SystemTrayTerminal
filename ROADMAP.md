# quickTERMINAL Roadmap

This roadmap reflects current priorities and may change.

## 1.0 Stabilization (Current)

- Fix PTY write-path reliability for large input bursts.
- Remove retain cycles in tab/split closure wiring.
- Tighten tab reorder consistency with repeated titles.
- Improve split restore correctness and persistence behavior.
- Add regression checks for parser and interaction edge cases.

## 1.1 Packaging and Distribution

- Signed app bundle build and notarization flow.
- Homebrew formula support.
- Versioned changelog and release artifacts.
- Optional auto-update strategy (to be decided).

## 1.2 UX and Terminal Fidelity

- ~~Better scrollback/search ergonomics.~~ **Done** — scrollback search with match highlighting (quickBAR `Search` command).
- Additional mouse/keyboard compatibility edge cases.
- ~~Expanded diagnostics for parser mode/state transitions.~~ **Done** — parser diagnostics overlay (quickBAR `Parser` command).
- ~~Performance instrumentation for redraw and PTY I/O paths.~~ **Done** — performance monitor overlay (quickBAR `Perf` command).

## Community and Project Health

- Triage labels and issue templates in active use.
- Contributor onboarding docs maintained.
- Security response process with release notes.
