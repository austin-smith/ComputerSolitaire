# Computer Solitaire Agent Guide

This file defines hard project constraints for any coding agent working in this repository.

## Platform + Framework Contract (Non-Negotiable)

- This app is **100% SwiftUI**.
- Do **not** add `UIKit` or `AppKit` usage.
- Do **not** add bridge layers like `UIViewRepresentable`, `NSViewRepresentable`, or wrapper shims unless explicitly requested by maintainers.
- Supported platforms are only:
  - iOS 26+
  - iPadOS 26+
  - macOS 26+
- We do **not** support older OS versions. Avoid backward-compatibility code paths.
- While building a feature, stay focused on the current-platform implementation; do not interrupt work to add backward-compatibility support unless a maintainer explicitly requests it.
- Do **not** introduce `if #available(...)` checks for older platforms unless a maintainer explicitly asks for them.

## Product Direction

- This is a modern native app. Prefer modern Swift and SwiftUI APIs.
- Use Liquid Glass design language where appropriate.
- Keep implementations clean, declarative, and platform-native.

## Code Expectations

- Prefer shared SwiftUI views and modifiers across platforms.
- Use platform conditionals (`#if os(iOS)`, `#if os(macOS)`) only when behavior truly differs.
- Keep state flow explicit and minimal; avoid over-engineering.
- Preserve accessibility, responsiveness, and animation smoothness.

## Quality Bar (Non-Negotiable)

- Maintain extremely high code quality standards in every change.
- Do not take shortcuts, add temporary hacks, or leave partial implementations.
- Follow best practices by default: clear naming, small focused types/functions, and maintainable architecture.
- Prefer robust, production-ready implementations over quick fixes.

## Branches, Commits, and Pull Requests

- Use plain lowercase kebab-case for branch names. Keep names descriptive and do not include issue numbers, prefixes, or namespaces such as `feature/`, `fix/`, usernames, or agent names.
- Before every commit or amend, show the exact current diff and validation, then get explicit approval. Branch or pull-request requests are not commit approval; later changes require fresh approval.
- Never amend, rebase, squash, reset, rewrite history, or force-push without explicit approval for that exact operation.
- Write commit messages entirely lowercase. Use the imperative mood for the subject, keep each commit focused on one logical change, do not use type or scope prefixes, and do not end the subject with a period. Add a body when the reason or important tradeoffs are not clear from the subject.
- Keep each pull request focused on one coherent change.
- Write concise, specific, imperative pull request titles in sentence case. Do not use prefixes or trailing periods, and make the title understandable without the branch name.
- Pull request descriptions must include `What Changed`, `Why`, and `Validation`. Include `UI Changes` only when the pull request changes the UI. Keep descriptions concise, self-contained, complete, and accurate to the final diff.
- Link any related issues in the pull request description; do not include issue numbers in branch names.
- Review the complete diff before opening a pull request. Update the title and description whenever the scope changes, and remove unrelated changes.

## Issues

- Search open and closed issues before creating a new issue.
- Keep each issue focused on one problem or change.
- Use a concise, specific, sentence-case title without type prefixes.
- Give enough context to understand the issue without first inspecting the code.
- For bugs, describe the current and expected behavior. Include reproduction steps, environment details, the game variant and relevant settings, and supporting evidence when available.
- For enhancements, explain the problem or goal, the desired outcome, and clear acceptance criteria.
- For UI issues, include screenshots. Include a short video when motion or interaction is relevant.
- Link any related issues and pull requests.
- Apply the appropriate existing labels when creating an issue: `bug` for bugs, `enhancement` for feature requests, and any applicable platform labels (`macOS`, `iOS`, `iPadOS`).

## What Agents Should Avoid

- No UIKit/AppKit imports.
- No legacy UI fallbacks.
- No compatibility hacks for pre-26 OS releases.
- No speculative abstraction layers that make SwiftUI code harder to read.

When in doubt, choose the simplest modern SwiftUI-first solution.

## Build Workflow

From repo root (`/Users/austinsmith/Developer/Repos/ComputerSolitaire`), run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project ComputerSolitaire.xcodeproj \
  -scheme ComputerSolitaire \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  build
```

For an iOS Simulator compile check without signing, run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project ComputerSolitaire.xcodeproj \
  -scheme ComputerSolitaire \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## Test Workflow

From repo root (`/Users/austinsmith/Developer/Repos/ComputerSolitaire`), run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project ComputerSolitaire.xcodeproj \
  -scheme ComputerSolitaire \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
```

Testing guidance:

- Add tests when they protect game rules, persistence, scoring, solver behavior, meaningful user-visible behavior, cross-file integration, bug regressions, or non-trivial logic that is easy to break.
- Do not add dedicated tests for every small helper extraction, straightforward computed property, or internal refactor unless the change introduces real behavioral risk.
- Prefer a small number of high-signal tests over many narrow tests that only restate the implementation.
