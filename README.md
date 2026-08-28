# Dino — Chrome Dinosaur in the Terminal (Zig)

Authentic recreation of the Chrome offline dino runner (`chrome://dino`) for your terminal, written in Zig 0.16 by **Flaxo**.

[![zig](https://img.shields.io/badge/zig-0.16-yellow)](https://ziglang.org)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![release](https://img.shields.io/badge/release-0.0.1-green)](https://github.com/flaxodotdev/dino/releases/tag/v0.0.1)

## Features — chrome parity

- **Same sprites** — T-Rex running (2-frame), jumping, ducking (2-frame), dead (`×` eye), cactus variants (small/large × single/double/triple), pterodactyl (2-frame wing flap) — all built from block characters (`█ ▄ ▀`) to match the chrome 1-bit art
- **Same physics** — gravity `0.12`, jump `-1.35`, duck-drop acceleration, tight AABB hitboxes (1px inset like chrome)
- **Same gameplay** — scrolling ground with procedural bumps, parallax clouds, increasing speed (`1.5 → 5.2`), distance-based score, `HI` vs current score (`00000` format), night mode invert every `700` points, progressive difficulty spawns pteros after `500`
- **Same vibe** — score at top-right, centered `G A M E  O V E R`, blink prompts, `Alt-screen` (`?1049h`) so scrollback is preserved

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
