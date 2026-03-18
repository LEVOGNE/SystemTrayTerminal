# Contributing to SystemTrayTerminal

Thanks for contributing.

## Before You Start

- Read the project [README.md](./README.md).
- Search existing issues and PRs to avoid duplicates.
- For security vulnerabilities, use [SECURITY.md](./SECURITY.md) instead of public issues.

## Local Setup

Requirements:

- macOS 13+
- Xcode Command Line Tools or full Xcode

Build:

```bash
bash build.sh
./SystemTrayTerminal
```

## Development Guidelines

- Keep changes focused and reviewable.
- Preserve the single-file architecture unless there is a strong reason to split.
- Add comments only where logic is non-obvious.
- Avoid unrelated refactors in bugfix PRs.
- Keep naming and style consistent with existing code.

## Pull Request Checklist

- PR title explains the change clearly.
- Include a short rationale: what changed and why.
- Include manual test notes with exact steps.
- Update docs when behavior or shortcuts changed.
- Confirm the project still builds with `bash build.sh`.

## Commit Guidance

Small commits are preferred. Suggested format:

`scope: short summary`

Examples:

- `parser: fix OSC 52 clipboard response handling`
- `ui: prevent split ratio from being overwritten on restore`

## Release Checklist

For maintainers publishing a new GitHub Release:

- [ ] Bump version in `kAppVersion` (SystemTrayTerminal.swift), `build_app.sh`, `build_zip.sh` — all three must match.
- [ ] Run `bash build.sh` — all tests must pass (0 failed).
- [ ] Run `bash build_zip.sh` — confirms `.app` bundle + `install.sh` + `FIRST_READ.txt` are in the ZIP.
- [ ] Generate SHA256 checksum and upload alongside the ZIP:
  ```bash
  shasum -a 256 SystemTrayTerminal.zip > SystemTrayTerminal.zip.sha256
  ```
  **Both files must be attached to the GitHub Release.** The updater downloads `SystemTrayTerminal.zip.sha256` and verifies the ZIP before installing. Missing the file downgrades the update to unverified (no hash check).
- [ ] Update `CHANGELOG.md` with the new version section.
- [ ] Tag the release: `git tag vX.Y.Z && git push origin vX.Y.Z`.

## What We Prioritize

- Stability and correctness of terminal behavior.
- Performance under sustained PTY output.
- Minimal binary size and fast startup.
- UX consistency for tray/toggle workflows.
