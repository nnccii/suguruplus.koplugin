# Suguru for KOReader

A [Suguru](https://en.wikipedia.org/wiki/Suguru) (also known as *Tectonic* or
*Nanbaburokku*) puzzle game for [KOReader](https://github.com/koreader/koreader),
designed for e-ink touch screens.

> The in-game text is in **French**.

## Rules

- Thick lines split the grid into regions of 1 to 5 cells.
- A region of N cells contains each digit from 1 to N exactly once.
- Two touching cells, even diagonally, never contain the same digit.

## Features

- Puzzles generated on the device: 5×5, 6×6, 7×7 and 8×8.
- Three levels, **all solvable by deduction, never by guessing**:
  - **Facile** (easy): basic rules only, extra clues.
  - **Moyen** (medium): basic rules only, minimal clues.
  - **Difficile** (hard): requires reasoning over every possible fill of a region.
- Notes, undo, error check, reveal solution.
- **Logical hints**: the Hint button frames the next deducible cell and says which
  rule finds it (or points at a mistake first).
- Automatic save and resume.
- Greyscale-friendly markers (no reliance on colour).

## Installation

1. Download `suguru.koplugin.zip` from the
   [latest release](../../releases/latest) and unzip it.
2. Copy the `suguru.koplugin` folder into KOReader's `plugins` folder
   (`koreader/plugins/` on Kindle and Kobo).
3. Restart KOReader, then open **Tools → Suguru**.

It can also be installed from KOReader with the
[App Store plugin](https://github.com/omer-faruq/appstore.koplugin).

## How puzzles are generated

1. **Regions and solution are built together**, cell by cell, with backtracking:
   each cell opens a region, joins the region on its left or above, or merges both.
   Each region gets a target size when created. A naive "random layout, then fill"
   approach fails on ~95% of layouts at 8×8; this one always succeeds.
2. **Clues are carved** from the full solution in random order. A clue is removed
   only if the puzzle remains solvable with the rule set of the chosen level, which
   also guarantees a unique solution.
3. The two rule sets:
   - **singles**: a cell with a single candidate; a digit with a single home in its region;
   - **witness**: enumerate every remaining fill of each region (at most 5! = 120);
     drop candidates that appear in no fill, and forbid in neighbouring cells any digit
     that sits next to them in every fill.

Typical generation time on a Kindle Paperwhite: 0.1–1 s (a few seconds at most
for 8×8 hard).

## Tests

The tests run with the LuaJIT bundled with KOReader, from the plugin folder:

```sh
luajit tests/test_brute.lua .   # solver and rules vs. naive exhaustive search
luajit tests/test_core.lua .    # generation, uniqueness, solvability, timing
luajit tests/test_ui_mock.lua . # UI flows with stubbed KOReader modules
```

## Credits

- UI adapted from [sudoku.koplugin](https://github.com/omer-faruq/sudoku.koplugin) (GPL-3.0).
- Witness rule and solvable carving ported from
  [sen-ltd/suguru](https://github.com/sen-ltd/suguru) (MIT).

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

GPL-3.0 — see [LICENSE](LICENSE).
