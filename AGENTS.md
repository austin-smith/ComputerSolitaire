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

## What Agents Should Avoid

- No UIKit/AppKit imports.
- No legacy UI fallbacks.
- No compatibility hacks for pre-26 OS releases.
- No speculative abstraction layers that make SwiftUI code harder to read.

When in doubt, choose the simplest modern SwiftUI-first solution.
