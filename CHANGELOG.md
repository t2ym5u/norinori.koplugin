# Changelog

All notable changes to this project will be documented in this file.

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
