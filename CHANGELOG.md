# Changelog

All notable changes to this project will be documented in this file.

## [1.0.5] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.0.4] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.0.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.0.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- First release: Norinori on 6×6, 8×8 and 10×10 grids, easy / medium / hard.
- Every puzzle has exactly one solution, proven by an exhaustive solver at
  generation, and is solvable by logic alone; the difficulty is the hardest
  technique the logical solver needs (counting and domino rules, region case
  analysis, one-step trial).
- Tap cycles shaded → dot → blank, hold blanks a cell; shaded cells that break
  a rule are crossed out as you play.
- Two-tap Hint, Undo, Restart, Show solution, timer, auto-save.
- A progress bar while a puzzle is generated, shown only when generation takes
  a moment (big grids on a slow device). Generation itself is fast: at most
  ~0.4 s on a desktop at every size and level, and a pure function of the
  random seed (no time limits), so the Daily Challenge is the same grid on
  every device.
