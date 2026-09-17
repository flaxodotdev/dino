# Dino — Chrome Dinosaur in the Terminal (Zig)

Authentic recreation of the Chrome offline dino runner (`chrome://dino`) for your terminal, written in Zig 0.16 by **Flaxo**.

[![zig](https://img.shields.io/badge/zig-0.16-yellow)](https://ziglang.org)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![release](https://img.shields.io/badge/release-0.0.1-green)](https://github.com/flaxodotdev/dino/releases/tag/v0.0.1)

## Features — chrome parity

- **Same sprites** — real pixel art, not ascii approximations. The T-Rex is a 20×20 downscale of chrome's 44×47 sprite (running 2-frame, jumping, ducking 2-frame, idle blink, dead), plus cactus variants (small/large × single/double/triple), 2-frame pterodactyl and outlined clouds
- **Half-block renderer** — the whole scene is composed on a pixel canvas where two pixels share one cell (`█ ▀ ▄`), so a pixel is square and the silhouettes match the chrome 1-bit art. Terminals too small for the full sprites get an automatic 2× downscale
- **Real day/night** — the canvas is painted, so the flip at every 700 points actually inverts: near-black with light sprites at night, light background with dark grey sprites by day. Starts at night and flips from there
- **Chrome's scoring** — `round(distance * 0.025)` in chrome pixels, normalised so terminals of different widths score at the same rate; the meter blinks three times with a blip on every hundred
- **Multi-box collision** — four boxes on the t-rex (head, neck, torso, legs) and three per cactus instead of one rectangle, so the snout and the tail stop killing you through empty space
- **Intro** — the ground slides in and the dino runs on from the left before the first obstacle
- **Same physics** — jump peaks at `1.2×` the dino height with a `~0.7s` airtime, duck fast-drop, tight AABB hitboxes (inset like chrome)
- **Same gameplay** — scrolling ground with procedural pebbles, parallax clouds, chrome's speed ramp (`6 → 13` px/frame, scaled to the dino width and to the terminal width), distance-based score, `HI` vs current score (`00000` format), night mode invert every `700` points, progressive difficulty spawns pteros after `450` at three heights (jump / jump / duck)
- **Ducking that holds** — terminals report no key-up, so the hold is inferred from auto-repeat with an adaptive window: the first press bridges the ~600ms repeat delay, then the window shrinks once repeats arrive. No duck/stand/duck stutter, and no way to get stuck ducking
- **Per-run history** — every run is appended to a plain-text file and `dino view` turns it into best score, longest run, most obstacles, averages and a bar chart of recent runs
- **Same vibe** — score at top-right, centered `G A M E  O V E R` with chrome's circular restart button, no colours chrome never uses, `Alt-screen` (`?1049h`) so scrollback is preserved

## Install

**One-liner (recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/flaxodotdev/dino/master/install.sh | sh
# custom prefix/version:
curl -fsSL https://raw.githubusercontent.com/flaxodotdev/dino/master/install.sh | sh -s -- --prefix ~/.local --version 0.0.1
```

**From source:**
```bash
zig build -Doptimize=ReleaseSmall
./zig-out/bin/dino
# or
zig build run

# install to PATH
zig build -Doptimize=ReleaseSmall -p ~/.local
# or copy universal binary
sudo cp dist/dino-macos-universal /usr/local/bin/dino
dino
```

Prebuilt binaries for `0.0.1` in [`dist/releases/`](dist/releases/): `dino-macos-universal` (universal), `dino-x86_64-linux-musl` (static), `dino-aarch64-linux-musl`, `*-linux-gnu`, etc.

## Commands

```bash
dino          # play
dino view     # stats from every run you have played
dino keys     # dump what your terminal sends for each key (input debugging)
dino help
```

Every finished run is appended as one tab-separated line to
`$XDG_DATA_HOME/dino/history.tsv` (falling back to `~/.local/share/dino/history.tsv`,
overridable with `$DINO_HISTORY`): start time, duration, score, obstacles cleared,
jumps, ducks, top speed and whether it ended in a death or a quit. Nothing leaves
your machine, and the file is plain text — `grep`, `awk` and `sort` all work on it.

`dino view` reports best score, longest run, most obstacles, averages, top speed,
deaths vs quits, and a bar chart of your last runs:

```
dino  -  37 runs, 12m 44s played

  best score       00412    16 Sep 21:04
  longest run      2m07s    16 Sep 21:04
  most obstacles   23       15 Sep 19:22
  ...
```

Top speed is normalised to chrome's px/frame, so runs recorded in terminals of
different widths stay comparable.

## Controls

| Key | Action |
|---|---|
| `Space` / `↑` / `W` / `K` | Jump (also start / restart) |
| `↓` / `S` / `J` | Duck (hold — terminal autorepeat keeps duck active; in air = fast-drop like chrome) |
| `R` / `Enter` | Restart when `GAME OVER` |
| `Q` / `Esc` / `Ctrl-C` | Quit |

Needs a TTY with at least `40×12`. Resize is handled live (`TIOCGWINSZ`).

## Implementation

- Single file: `src/main.zig` (~1100 lines), zero dependencies
- Raw mode via `tcgetattr`/`tcsetattr` (echo/icanon/isig off, `VMIN=0 VTIME=1`)
- Non-blocking input via `poll(STDIN, 0)` + `read`, escape sequences for arrows (`\x1b[A/B`)
- Fixed-timestep loop at 60 FPS (`CLOCK_MONOTONIC` + `nanosleep`), `alt-screen` + hide cursor (`?25l`/`?25h`) with defer restore
- `std.ArrayList` (Zig 0.16 unmanaged — `.empty` + `alloc` param) for obstacles/clouds, frame buffer built with ANSI `H`/`2J` and `print(alloc, ...)`
- Random via `std.Random.DefaultPrng` seeded from `clock_gettime`

## Project Layout

```
.
├── build.zig       # exe + install + run/test steps
├── build.zig.zon   # package manifest (0.0.1)
├── src/
│   ├── main.zig    # the game
│   └── root.zig    # library stub (unused)
├── dist/releases/  # prebuilt 0.0.1 binaries
└── zig-out/bin/dino
```

## Release 0.0.1

First public release by Flaxo — chrome-parity terminal dino, tuned jump (8.3 rows peak), fair spacing, speed ramp `1.5→5.2`.

```bash
git tag v0.0.1
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl -p dist/...
```

## License

MIT © 2026 Flaxo — see [LICENSE](LICENSE).

Have fun! `dino` is the same dino you know, just in 80 columns.
