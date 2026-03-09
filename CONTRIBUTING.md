# Contributing to quickTERMINAL

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
./quickTerminal
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

## What We Prioritize

- Stability and correctness of terminal behavior.
- Performance under sustained PTY output.
- Minimal binary size and fast startup.
- UX consistency for tray/toggle workflows.
