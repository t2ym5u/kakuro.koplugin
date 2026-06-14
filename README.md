# kakuro.koplugin

A Kakuro plugin for [KOReader](https://github.com/koreader/koreader).


## Screenshot

*(Screenshot to be added.)*

## Rules

Fill each run of white cells with digits 1–9 that sum to the clue shown. No digit may be repeated within a single run. Runs are separated by shaded clue cells (across clue in bottom-left triangle, down clue in top-right triangle).

## Concept

Kakuro is the numerical equivalent of a crossword puzzle. Fill white cells with
digits 1–9 so that each horizontal and vertical run sums to the clue shown in the
black cell to its left or above. No digit may repeat within a run.

## Features

- **Multiple grid sizes** — Small (6×6), Medium (9×9), Large (12×12)
- **Three difficulty levels** — Easy, Medium, Hard
- **Note mode** — pencil in candidate digits as small annotations
- **Sum highlighting** — tap a clue to highlight its corresponding run
- **Digit completion** — a digit button is greyed out when it cannot appear in the selected run
- **Check** — highlights cells that violate a run constraint
- **Reveal solution** — shows the full solution (disables editing)
- **Undo** — step back through your moves
- **Auto-save** — game state is saved and restored on next launch

## Controls

| Action | How |
|--------|-----|
| Select a cell | Tap it |
| Enter a digit | Tap the digit button |
| Erase a cell | Tap **Erase** |
| Toggle note mode | Tap **Note: Off / On** |
| Undo last move | Tap **Undo** |
| Check progress | Tap **Check** |
| New game | Tap **New game** |
| Change grid size | Tap **Grid** |
| Change difficulty | Tap **Diff** |
| Show rules | Tap **Rules** |

## Why e-ink friendly?

Like Sudoku, Kakuro is a pure logic puzzle with discrete tap interactions and
static grid rendering — well-suited to e-ink refresh characteristics.

## License

GPL-3.0
