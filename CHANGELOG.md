# Changelog

All notable changes to this project will be documented in this file.

## [1.1.1] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.1.0] - 2026-11-05

### Changed
- Hard no longer needs a guess. Until now every Hard grid could only be
  finished by shading a cell and seeing the rules break ("what if this cell
  were shaded?"). Hard now takes the same reasoning as Medium (trying every
  way a region can still take its two shaded cells and keeping what they all
  agree on), but several times as often: Medium needs it 1 to 4 times
  depending on the size, Hard at least 4 (6×6), 6 (8×8) or 8 (10×10) times.
- Hard and Medium grids differ from those of 1.0.x for the same seed, so the
  Daily Challenge may show a different Norinori grid once.
- Faster generation: region case analysis plays each case on the grid and
  undoes it instead of copying the grid, skips the small regions it has
  just tried, and a layout the generator has already graded is not graded
  again. Worst case over 50 seeds on a desktop: 10×10 ~0.35–0.45 s →
  ~0.15–0.3 s, 8×8 Hard ~0.22 s → ~0.1 s. Same puzzles for the same seed.

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
