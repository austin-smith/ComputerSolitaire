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

## What Agents Should Avoid

- No UIKit/AppKit imports.
- No legacy UI fallbacks.
- No compatibility hacks for pre-26 OS releases.
- No speculative abstraction layers that make SwiftUI code harder to read.

When in doubt, choose the simplest modern SwiftUI-first solution.

## Build Workflow

This command builds the macOS destination only.

From repo root (`/Users/austinsmith/Developer/Repos/ComputerSolitaire`), run:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project ComputerSolitaire.xcodeproj \
  -scheme ComputerSolitaire \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  build
```
