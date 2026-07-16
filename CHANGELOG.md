# Changelog

## 0.8.3 - 2026-07-15

### Added

- Sparkle update checks for the direct-download macOS build, including a Check for Updates command and an automatic update-check setting. ([#78](https://github.com/austin-smith/ComputerSolitaire/pull/78))

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.8.2...v0.8.3

## 0.8.2 - 2026-07-15

### Added

- Animation Speed setting with Normal, Fast, and Instant options; Reduce Motion now suppresses gameplay animations and the win cascade. ([#76](https://github.com/austin-smith/ComputerSolitaire/pull/76), [#77](https://github.com/austin-smith/ComputerSolitaire/pull/77))
- Blue and Pink alternate app icons. ([#74](https://github.com/austin-smith/ComputerSolitaire/pull/74))

### Changed

- Updated the primary app icon from blue to teal. ([#74](https://github.com/austin-smith/ComputerSolitaire/pull/74))

### Fixed

- Restored card-flight animations for tap-to-move, drag-and-drop, auto-finish, and invalid-drop returns. ([#75](https://github.com/austin-smith/ComputerSolitaire/pull/75))

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.8.1...v0.8.2

## 0.8.1 - 2026-07-14

### Fixed

#### Performance

- Reduced per-move rendering across all ten games by limiting animation transactions to affected board regions and skipping unchanged cards, piles, and top rows. ([#70](https://github.com/austin-smith/ComputerSolitaire/pull/70), [#72](https://github.com/austin-smith/ComputerSolitaire/pull/72))
- Moved saved-game sanitization and JSON encoding off the main thread and skipped superseded autosaves. ([#70](https://github.com/austin-smith/ComputerSolitaire/pull/70))
- Limited per-frame drag and win-cascade updates to their overlays instead of re-evaluating the entire board, while preserving structural SwiftUI diffing through the main scene. ([#71](https://github.com/austin-smith/ComputerSolitaire/pull/71))
- Short-circuited FreeCell auto-finish availability checks when cascade ordering cannot complete, avoiding a full win simulation on most moves. ([#70](https://github.com/austin-smith/ComputerSolitaire/pull/70))

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.8.0...v0.8.1

## 0.8.0 - 2026-07-14

### Added

#### Eight new game variants

Each variant includes its own solver-backed hints, persistence, rules and scoring, statistics, and accessibility support.

- Spider ([#48](https://github.com/austin-smith/ComputerSolitaire/pull/48))
- Pyramid ([#47](https://github.com/austin-smith/ComputerSolitaire/pull/47))
- TriPeaks ([#52](https://github.com/austin-smith/ComputerSolitaire/pull/52))
- Golf ([#58](https://github.com/austin-smith/ComputerSolitaire/pull/58))
- Yukon ([#42](https://github.com/austin-smith/ComputerSolitaire/pull/42))
- Scorpion ([#60](https://github.com/austin-smith/ComputerSolitaire/pull/60))
- Forty Thieves ([#61](https://github.com/austin-smith/ComputerSolitaire/pull/61))
- Canfield ([#63](https://github.com/austin-smith/ComputerSolitaire/pull/63))

#### Settings and feedback

- Option to disable haptic feedback on iOS ([#66](https://github.com/austin-smith/ComputerSolitaire/pull/66))
- Option to hide in-game statistics ([#66](https://github.com/austin-smith/ComputerSolitaire/pull/66))
- Option to hide stock counts ([#66](https://github.com/austin-smith/ComputerSolitaire/pull/66))
- Haptic feedback for starting auto-finish and winning games ([#62](https://github.com/austin-smith/ComputerSolitaire/pull/62))

### Changed

- Replaced Settings-based game selection with an on-board game picker. ([#53](https://github.com/austin-smith/ComputerSolitaire/pull/53))
- Each game mode now keeps its own saved session and statistics; switching modes pauses the current game instead of ending it. ([#53](https://github.com/austin-smith/ComputerSolitaire/pull/53))
- The game picker now indicates overflow with edge fades and opens with the current game in view. ([#68](https://github.com/austin-smith/ComputerSolitaire/pull/68))
- Redesigned Statistics as a cross-game overview with per-game detail and mode-specific breakdowns. ([#53](https://github.com/austin-smith/ComputerSolitaire/pull/53))
- Reorganized the iOS toolbar to keep Hint and Undo visible, show Auto Finish only when available, and move other actions into the More menu. ([#62](https://github.com/austin-smith/ComputerSolitaire/pull/62))
- Reorganized the macOS toolbar with contextual Auto Finish, grouped Hint and Undo controls, and a combined New Game and Redeal menu. ([#62](https://github.com/austin-smith/ComputerSolitaire/pull/62))
- Reorganized Settings into focused sections with dedicated appearance pages. ([#66](https://github.com/austin-smith/ComputerSolitaire/pull/66))
- Replaced the macOS settings sheet with a standard Settings window. ([#66](https://github.com/austin-smith/ComputerSolitaire/pull/66))
- Rules & Scoring can now display any game instead of only the game in progress. ([#66](https://github.com/austin-smith/ComputerSolitaire/pull/66))
- Added macOS keyboard shortcuts for switching directly between games. ([#64](https://github.com/austin-smith/ComputerSolitaire/pull/64))
- Moved statistics reset actions from the iOS toolbar into the statistics form. ([#64](https://github.com/austin-smith/ComputerSolitaire/pull/64))
- Revised the Rules & Scoring text across all ten games for consistent terminology. ([#64](https://github.com/austin-smith/ComputerSolitaire/pull/64))
- Added staggered stock-to-tableau deal animations and in-flight card flips for Spider and Scorpion. ([#60](https://github.com/austin-smith/ComputerSolitaire/pull/60), [#61](https://github.com/austin-smith/ComputerSolitaire/pull/61))

### Fixed

- Restoring a saved game no longer replaces its board when the saved variant differs from the stored game setting. ([#47](https://github.com/austin-smith/ComputerSolitaire/pull/47))
- Undoing Klondike stock draws and waste recycles now flips returning cards during their flights instead of snapping their face state at landing. ([#60](https://github.com/austin-smith/ComputerSolitaire/pull/60))

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.7.0...v0.8.0

## 0.7.0 - 2026-07-12

### Added

- New FreeCell game mode, including supermoves, hints, auto-finish, persistence, rules, and statistics. ([#26](https://github.com/austin-smith/ComputerSolitaire/pull/26))
- Per-variant and combined statistics for Klondike and FreeCell. ([#26](https://github.com/austin-smith/ComputerSolitaire/pull/26))
- Pixel and Simple card styles. ([#26](https://github.com/austin-smith/ComputerSolitaire/pull/26), [#32](https://github.com/austin-smith/ComputerSolitaire/pull/32))
- Configurable card-back colors. ([#32](https://github.com/austin-smith/ComputerSolitaire/pull/32))
- Alternate app icons. ([#28](https://github.com/austin-smith/ComputerSolitaire/pull/28))
- About page on iOS. ([#34](https://github.com/austin-smith/ComputerSolitaire/pull/34))

### Changed

- Redesigned the hint and move-advisor system with variant-specific logic, improved Klondike planning, solver-backed FreeCell hints, and updated tap-to-move behavior. ([#26](https://github.com/austin-smith/ComputerSolitaire/pull/26))
- Redesigned Settings. ([#30](https://github.com/austin-smith/ComputerSolitaire/pull/30), [#32](https://github.com/austin-smith/ComputerSolitaire/pull/32))
- Updated card rendering, board sizing, draw animations, and felt rendering. ([#32](https://github.com/austin-smith/ComputerSolitaire/pull/32))
- Improved VoiceOver labels, selected states, and card/pile exposure. ([#39](https://github.com/austin-smith/ComputerSolitaire/pull/39))

### Fixed

- Draw-one recycle penalties now use the draw mode selected when the game was dealt. ([#29](https://github.com/austin-smith/ComputerSolitaire/pull/29))

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.6.0...v0.7.0

## 0.6.0 - 2026-02-23

### What's Changed

* Enhance statistics view in https://github.com/austin-smith/ComputerSolitaire/pull/18
* Add macOS menu bar game controls in https://github.com/austin-smith/ComputerSolitaire/pull/19
* Add comprehensive unit tests in https://github.com/austin-smith/ComputerSolitaire/pull/20

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.5.0...v0.6.0

## 0.5.0 - 2026-02-21

### What's Changed

* Fix iOS SFX playback in silent mode in https://github.com/austin-smith/ComputerSolitaire/pull/4
* Haptic feedback for iOS in https://github.com/austin-smith/ComputerSolitaire/pull/5
* Replace AppKit & UIKit usage with SwiftUI in https://github.com/austin-smith/ComputerSolitaire/pull/6
* Code cleanup & optimization in https://github.com/austin-smith/ComputerSolitaire/pull/7
* Prevent board clipping with responsive board scaling in https://github.com/austin-smith/ComputerSolitaire/pull/8
* Add hint system in https://github.com/austin-smith/ComputerSolitaire/pull/9
* Cache hint availability to reduce recycle lag in https://github.com/austin-smith/ComputerSolitaire/pull/10
* Add win cascade celebration animation in https://github.com/austin-smith/ComputerSolitaire/pull/11
* Hint system improvements and macOS CI test workflow in https://github.com/austin-smith/ComputerSolitaire/pull/12

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.4.1...v0.5.0

## 0.4.1 - 2026-02-16

### What's Changed

* Add code signing & notary steps to GitHub release action in https://github.com/austin-smith/ComputerSolitaire/pull/3

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.4.0...v0.4.1

## 0.4.0 - 2026-02-16

### What's Changed

* Ensure timer is paused when menus are open in https://github.com/austin-smith/ComputerSolitaire/pull/2

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/compare/v0.3.0...v0.4.0

## 0.3.0 - 2026-02-16

### What's Changed

* Base game functionality
* Scoring and stats in https://github.com/austin-smith/ComputerSolitaire/pull/1

**Full Changelog**: https://github.com/austin-smith/ComputerSolitaire/commits/v0.3.0
