const std = @import("std");
const posix = std.posix;
const c = std.c;

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const FPS: u64 = 60;
const FRAME_NS: u64 = 1_000_000_000 / FPS;
const DINO_X: i32 = 6; // fixed column where dino lives

// Physics are authored for the full scale dino (20 pixels tall) and are
// multiplied by Game.scale() when the half scale sprites are in use.
// peak = v^2 / (2g) = 2.30^2 / 0.22 ~= 24 px  (1.2x the dino, like chrome)
// airtime = 2v/g ~= 42 frames ~= 0.7s
const BASE_GRAVITY: f32 = 0.11;
const BASE_JUMP_VEL: f32 = -2.30;
const BASE_DROP_ACC: f32 = 0.45; // extra gravity while fast-dropping

// chrome runs at 6 px/frame with a 44 px wide dino and tops out at 13.
const SPEED_PER_DINO_W: f32 = 6.0 / 44.0;
const MAX_SPEED_RATIO: f32 = 13.0 / 6.0;
const ACCEL_RATIO: f32 = 0.001 / 6.0;
// chrome's canvas is 600 px wide == 13.6 dino widths
const CANVAS_DINO_WIDTHS: f32 = 13.6;

const GROUND_ROW_FROM_BOTTOM: i32 = 3; // ground line sits at height - 3

// chrome's distance meter counts round(distance * 0.025) in its own pixels, so
// 100 points is ~11s of running and 700 (the night flip) is well over a minute
const SCORE_PER_CHROME_PX: f32 = 0.025;
const CHROME_DINO_W: f32 = 44.0;

const INTRO_FRAMES: i32 = 45; // ground slides in, dino runs on from the left
const FLASH_PHASE_FRAMES: u64 = 15; // 250ms, same as chrome
const FLASH_PHASES: u64 = 6; // three on/off blinks

// ---------------------------------------------------------------------------
// Sprites
//
// Every sprite is pixel art: one character per pixel, '#' = filled.
// Vertically two pixels share one terminal cell (rendered with the half blocks
// U+2588 U+2580 U+2584), so a pixel is roughly square in a normal terminal font.
//
// The dino is a 20x20 downscale of chrome's 44x47 t-rex. Holes (eye, mouth)
// are aligned to even coordinates so they survive the automatic 2x downscale
// used on small terminals.
// ---------------------------------------------------------------------------

const DINO_IDLE = [_][]const u8{
    "...........########.",
    "..........##########",
    "..........##..######",
    "..........##..######",
    "..........##########",
    "..........##########",
    "..........####......",
    ".........#########..",
    "........######......",
    "......########......",
    "..############......",
    "###############.....",
    "################....",
    "....###########.....",
    ".....########.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....####.####......",
};

// idle blink - chrome's dino winks while it waits
const DINO_BLINK = [_][]const u8{
    "...........########.",
    "..........##########",
    "..........##########",
    "..........##########",
    "..........##########",
    "..........##########",
    "..........####......",
    ".........#########..",
    "........######......",
    "......########......",
    "..############......",
    "###############.....",
    "################....",
    "....###########.....",
    ".....########.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....####.####......",
};

// run frame A - rear leg planted, front leg lifted
const DINO_RUN_A = [_][]const u8{
    "...........########.",
    "..........##########",
    "..........##..######",
    "..........##..######",
    "..........##########",
    "..........##########",
    "..........####......",
    ".........#########..",
    "........######......",
    "......########......",
    "..############......",
    "###############.....",
    "################....",
    "....###########.....",
    ".....########.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..####......",
    ".....###............",
    ".....####...........",
};

// run frame B - front leg planted, rear leg lifted
const DINO_RUN_B = [_][]const u8{
    "...........########.",
    "..........##########",
    "..........##..######",
    "..........##..######",
    "..........##########",
    "..........##########",
    "..........####......",
    ".........#########..",
    "........######......",
    "......########......",
    "..############......",
    "###############.....",
    "################....",
    "....###########.....",
    ".....########.......",
    ".....###..###.......",
    ".....###..###.......",
    "....####..###.......",
    "..........###.......",
    "..........####......",
};

// jump - legs together, tucked
const DINO_JUMP = [_][]const u8{
    "...........########.",
    "..........##########",
    "..........##..######",
    "..........##..######",
    "..........##########",
    "..........##########",
    "..........####......",
    ".........#########..",
    "........######......",
    "......########......",
    "..############......",
    "###############.....",
    "################....",
    "....###########.....",
    ".....########.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....####.####......",
};

// dead - eye shut, jaw dropped
const DINO_DEAD = [_][]const u8{
    "...........########.",
    "..........##########",
    "..........##....####",
    "..........##....####",
    "..........##########",
    "..........##########",
    "..........####......",
    ".........#####......",
    "........######......",
    "......########......",
    "..############......",
    "###############.....",
    "################....",
    "....###########.....",
    ".....########.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....###..###.......",
    ".....####.####......",
};

// ducking dino - chrome's 59x30 sprite, stretched low and long
const DINO_DUCK_A = [_][]const u8{
    "..................#######.",
    ".................#########",
    ".................##..#####",
    ".................##..#####",
    ".................####.....",
    "................#########.",
    "..###################.....",
    "####################......",
    ".#################........",
    ".....###...###............",
    ".....###...###............",
    ".....####..####...........",
};

const DINO_DUCK_B = [_][]const u8{
    "..................#######.",
    ".................#########",
    ".................##..#####",
    ".................##..#####",
    ".................####.....",
    "................#########.",
    "..###################.....",
    "####################......",
    ".#################........",
    ".....###...###............",
    ".....###...###............",
    "....####..####............",
};

// cactus - chrome's two sizes, trunk plus one arm on each side
const CACTUS_SMALL = [_][]const u8{
    "....##...",
    "....##...",
    "....##...",
    "....##...",
    ".##.##...",
    ".##.##...",
    ".##.##.##",
    ".#####.##",
    "....##.##",
    "....#####",
    "....##...",
    "....##...",
    "....##...",
    "....##...",
};

const CACTUS_LARGE = [_][]const u8{
    ".....###.....",
    ".....###.....",
    ".....###.....",
    ".....###.....",
    ".....###.....",
    ".###.###.....",
    ".###.###.....",
    ".###.###.###.",
    ".###.###.###.",
    ".#######.###.",
    ".#######.###.",
    ".....#######.",
    ".....#######.",
    ".....###.....",
    ".....###.....",
    ".....###.....",
    ".....###.....",
    ".....###.....",
    ".....###.....",
    ".....###.....",
};

// pterodactyl - flies left, wings up / wings down
const PTERO_A = [_][]const u8{
    "......#####.....",
    ".....######.....",
    "....######......",
    "...######.......",
    "..######........",
    "#########.####..",
    "##############..",
    "....#######.....",
    ".....#####......",
    "......###.......",
};

const PTERO_B = [_][]const u8{
    "......###.......",
    ".....#####......",
    "....#######.....",
    "#########.####..",
    "##############..",
    "..#######.......",
    "...######.......",
    "....######......",
    ".....######.....",
    "......#####.....",
};

// restart button - chrome's circular arrow, shown on the game over screen
const RESTART = [_][]const u8{
    "....####....",
    "..##....##..",
    ".##......###",
    "##........##",
    "##........##",
    "##........##",
    "##........##",
    "##........##",
    ".##......##.",
    "..##....##..",
    "....####....",
};

// cloud - chrome draws it as an outline
const CLOUD = [_][]const u8{
    "....######....",
    "..##......##..",
    ".##........##.",
    "##..........##",
    "#............#",
    ".############.",
};

// ---------------------------------------------------------------------------
// Sprite helpers - '#' lookup, with optional 2x downscale for small terminals
// ---------------------------------------------------------------------------
const Art = []const []const u8;

fn artOn(art: Art, x: i32, y: i32) bool {
    if (y < 0 or x < 0) return false;
    const uy: usize = @intCast(y);
    if (uy >= art.len) return false;
    const row = art[uy];
    const ux: usize = @intCast(x);
    if (ux >= row.len) return false;
    return row[ux] == '#';
}

/// Sample one output pixel. At half scale a 2x2 source block lights up when at
/// least two of its four pixels are filled.
fn artPixel(art: Art, x: i32, y: i32, half: bool) bool {
    if (!half) return artOn(art, x, y);
    var n: u32 = 0;
    if (artOn(art, x * 2, y * 2)) n += 1;
    if (artOn(art, x * 2 + 1, y * 2)) n += 1;
    if (artOn(art, x * 2, y * 2 + 1)) n += 1;
    if (artOn(art, x * 2 + 1, y * 2 + 1)) n += 1;
    return n >= 2;
}

fn artW(art: Art, half: bool) i32 {
    const w: i32 = @intCast(art[0].len);
    return if (half) @divTrunc(w + 1, 2) else w;
}

fn artH(art: Art, half: bool) i32 {
    const h: i32 = @intCast(art.len);
    return if (half) @divTrunc(h + 1, 2) else h;
}

// ---------------------------------------------------------------------------
// Collision boxes
//
// One rectangle around a t-rex is mostly empty space - the snout is top right,
// the tail is mid left - so corners kill you unfairly. Chrome splits each
// sprite into a handful of boxes instead; these are the same idea, in sprite
// pixel coordinates.
// ---------------------------------------------------------------------------
const Rect = struct { x: i32, y: i32, w: i32, h: i32 };

const DINO_BOXES = [_]Rect{
    .{ .x = 10, .y = 0, .w = 10, .h = 8 }, // head and snout
    .{ .x = 7, .y = 7, .w = 8, .h = 4 }, // neck and chest
    .{ .x = 3, .y = 10, .w = 13, .h = 5 }, // torso, arm, tail root
    .{ .x = 5, .y = 14, .w = 9, .h = 6 }, // legs
};

const DINO_DUCK_BOXES = [_]Rect{
    .{ .x = 16, .y = 0, .w = 10, .h = 6 },
    .{ .x = 1, .y = 6, .w = 20, .h = 3 },
    .{ .x = 5, .y = 9, .w = 10, .h = 3 },
};

const CACTUS_SMALL_BOXES = [_]Rect{
    .{ .x = 4, .y = 0, .w = 2, .h = 14 },
    .{ .x = 1, .y = 4, .w = 2, .h = 4 },
    .{ .x = 7, .y = 6, .w = 2, .h = 4 },
};

const CACTUS_LARGE_BOXES = [_]Rect{
    .{ .x = 5, .y = 0, .w = 3, .h = 20 },
    .{ .x = 1, .y = 5, .w = 3, .h = 6 },
    .{ .x = 9, .y = 7, .w = 3, .h = 6 },
};

const PTERO_BOXES = [_]Rect{
    .{ .x = 0, .y = 3, .w = 6, .h = 3 }, // beak and head
    .{ .x = 5, .y = 2, .w = 10, .h = 5 }, // body
};

/// Sprite-space box to screen-pixel box; at half scale it has to round outward
/// so a box never shrinks to nothing.
fn scaleRect(b: Rect, half: bool) Rect {
    if (!half) return b;
    const x = @divTrunc(b.x, 2);
    const y = @divTrunc(b.y, 2);
    return .{
        .x = x,
        .y = y,
        .w = @max(1, @divTrunc(b.x + b.w + 1, 2) - x),
        .h = @max(1, @divTrunc(b.y + b.h + 1, 2) - y),
    };
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
const ObstacleKind = enum { cactus_small, cactus_large, ptero };

const PteroHeight = enum { low, mid, high };

const Obstacle = struct {
    x: f32,
    kind: ObstacleKind,
    count: u8 = 1,
    level: PteroHeight = .low,
};

const Cloud = struct {
    x: f32,
    y: i32, // pixel row
};

const GameState = enum { idle, playing, game_over };

// pixel colour ids
const C_DINO: u8 = 1;
const C_CACTUS: u8 = 2;
const C_CLOUD: u8 = 3;
const C_GROUND: u8 = 4;

const Game = struct {
    width: i32,
    height: i32,
    half: bool = false,
    state: GameState = .idle,
    dino_y: f32 = 0, // pixels above ground (negative = airborne)
    dino_vy: f32 = 0,
    on_ground: bool = true,
    ducking: bool = false,
    frame: u64 = 0,
    score: u32 = 0,
    score_f: f32 = 0,
    hi_score: u32 = 0,
    intro: i32 = 0,
    flash_start: u64 = 0,
    flashing: bool = false,
    pending_beep: bool = false,
    speed: f32 = 1,
    ground_scroll: f32 = 0,
    allocator: std.mem.Allocator,
    obstacles: std.ArrayList(Obstacle),
    clouds: std.ArrayList(Cloud),
    next_spawn_dist: f32 = 40,
    dist_since_spawn: f32 = 0,
    blink: bool = false,
    rng: std.Random.DefaultPrng,
    inverted: bool = true, // start at night; the flip at 700 goes to day
    // pixel canvas: width x (2 * height)
    px: []u8 = &.{},
    px_w: i32 = 0,
    px_h: i32 = 0,

    fn init(alloc: std.mem.Allocator, w: i32, h: i32) Game {
        var ts: c.timespec = undefined;
        _ = c.clock_gettime(c.CLOCK.MONOTONIC, &ts);
        const seed: u64 = @as(u64, @intCast(ts.sec)) *% 1000000000 ^ @as(u64, @intCast(ts.nsec));
        const prng = std.Random.DefaultPrng.init(seed);
        return .{
            .width = w,
            .height = h,
            .allocator = alloc,
            .obstacles = .empty,
            .clouds = .empty,
            .rng = prng,
        };
    }

    fn deinit(self: *Game) void {
        self.obstacles.deinit(self.allocator);
        self.clouds.deinit(self.allocator);
        if (self.px.len != 0) self.allocator.free(self.px);
    }

    // -- scale -------------------------------------------------------------
    /// Terminals that cannot fit the 20px dino plus a full jump fall back to
    /// the automatically downscaled 10px sprites.
    fn pickScale(self: *Game) void {
        self.half = self.height < 26 or self.width < 90;
    }

    fn scale(self: *Game) f32 {
        return if (self.half) 0.5 else 1.0;
    }

    fn dinoW(self: *Game) i32 {
        return artW(&DINO_IDLE, self.half);
    }

    fn dinoH(self: *Game) i32 {
        return artH(&DINO_IDLE, self.half);
    }

    fn gravity(self: *Game) f32 {
        return BASE_GRAVITY * self.scale();
    }

    fn jumpVel(self: *Game) f32 {
        return BASE_JUMP_VEL * self.scale();
    }

    /// Narrow terminals show fewer dino-widths than chrome's canvas, so the
    /// world scrolls proportionally slower and reaction time stays honest.
    fn widthScale(self: *Game) f32 {
        const target = CANVAS_DINO_WIDTHS * @as(f32, @floatFromInt(self.dinoW()));
        const got = @as(f32, @floatFromInt(self.width)) / target;
        return std.math.clamp(got, 0.5, 1.0);
    }

    fn baseSpeed(self: *Game) f32 {
        return SPEED_PER_DINO_W * @as(f32, @floatFromInt(self.dinoW())) * self.widthScale();
    }

    fn maxSpeed(self: *Game) f32 {
        return self.baseSpeed() * MAX_SPEED_RATIO;
    }

    // -- geometry ----------------------------------------------------------
    /// Pixel row of the ground line. Sprites stand on groundPy() - 1.
    fn groundPy(self: *Game) i32 {
        return (self.height - GROUND_ROW_FROM_BOTTOM) * 2;
    }

    /// Column the dino stands in. During the intro it runs on from off-screen.
    fn dinoX(self: *Game) i32 {
        if (self.intro <= 0) return DINO_X;
        const slide_frames: i32 = @divTrunc(INTRO_FRAMES * 2, 3);
        const done = INTRO_FRAMES - self.intro;
        if (done >= slide_frames) return DINO_X;
        const start = -self.dinoW();
        const t = @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(slide_frames));
        const span: f32 = @floatFromInt(DINO_X - start);
        return start + @as(i32, @intFromFloat(@round(span * t)));
    }

    /// How much of the ground has slid in during the intro, in columns.
    fn introGroundW(self: *Game) i32 {
        if (self.intro <= 0) return self.width;
        const done = INTRO_FRAMES - self.intro;
        const t = @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(INTRO_FRAMES));
        return @intFromFloat(@round(@as(f32, @floatFromInt(self.width)) * t));
    }

    fn dinoArt(self: *Game) Art {
        if (self.state == .game_over) return &DINO_DEAD;
        if (!self.on_ground) return &DINO_JUMP;
        if (self.ducking) {
            return if ((self.frame / 6) % 2 == 0) @as(Art, &DINO_DUCK_A) else @as(Art, &DINO_DUCK_B);
        }
        if (self.state == .idle and self.intro <= 0) {
            return if (self.blink and (self.frame / 20) % 8 == 0) @as(Art, &DINO_BLINK) else @as(Art, &DINO_IDLE);
        }
        return if ((self.frame / 6) % 2 == 0) @as(Art, &DINO_RUN_A) else @as(Art, &DINO_RUN_B);
    }

    /// Top pixel row of the dino for the given sprite.
    fn dinoTopPy(self: *Game, art: Art) i32 {
        const bottom = self.groundPy() - 1;
        const h = artH(art, self.half);
        const base = bottom - h + 1;
        if (self.ducking and self.on_ground) return base;
        return base + @as(i32, @intFromFloat(@floor(self.dino_y)));
    }

    fn dinoBoxes(self: *Game) []const Rect {
        return if (self.ducking and self.on_ground) &DINO_DUCK_BOXES else &DINO_BOXES;
    }

    fn obstacleBoxes(_: *Game, o: Obstacle) []const Rect {
        return switch (o.kind) {
            .cactus_small => &CACTUS_SMALL_BOXES,
            .cactus_large => &CACTUS_LARGE_BOXES,
            .ptero => &PTERO_BOXES,
        };
    }

    fn obstacleArt(self: *Game, o: Obstacle) Art {
        return switch (o.kind) {
            .cactus_small => &CACTUS_SMALL,
            .cactus_large => &CACTUS_LARGE,
            .ptero => if ((self.frame / 9) % 2 == 0) @as(Art, &PTERO_A) else @as(Art, &PTERO_B),
        };
    }

    fn cactusGap(self: *Game) i32 {
        return if (self.half) 1 else 2;
    }

    fn obstacleW(self: *Game, o: Obstacle) i32 {
        const w = artW(self.obstacleArt(o), self.half);
        const n: i32 = @intCast(o.count);
        return w * n + self.cactusGap() * (n - 1);
    }

    /// Top pixel row of an obstacle.
    fn obstacleTopPy(self: *Game, o: Obstacle) i32 {
        const art = self.obstacleArt(o);
        const h = artH(art, self.half);
        const bottom = self.groundPy() - 1;
        if (o.kind != .ptero) return bottom - h + 1;
        const lift: i32 = switch (o.level) {
            .low => 0,
            .mid => @intFromFloat(6 * self.scale()),
            .high => @intFromFloat(12 * self.scale()),
        };
        return bottom - lift - h + 1;
    }

    /// Cheap whole-sprite test first, then chrome's per-box pass.
    fn collides(self: *Game, o: Obstacle) bool {
        const dart = self.dinoArt();
        const dx = self.dinoX();
        const dy = self.dinoTopPy(dart);
        const oart = self.obstacleArt(o);
        const ox: i32 = @intFromFloat(@round(o.x));
        const oy = self.obstacleTopPy(o);

        const dino_rect: Rect = .{ .x = dx, .y = dy, .w = artW(dart, self.half), .h = artH(dart, self.half) };
        const obs_rect: Rect = .{ .x = ox, .y = oy, .w = self.obstacleW(o), .h = artH(oart, self.half) };
        if (!rectsOverlap(dino_rect, obs_rect)) return false;

        const step = artW(oart, self.half) + self.cactusGap();
        for (self.dinoBoxes()) |raw_a| {
            const ba = scaleRect(raw_a, self.half);
            const a: Rect = .{ .x = dx + ba.x, .y = dy + ba.y, .w = ba.w, .h = ba.h };
            var n: i32 = 0;
            while (n < @as(i32, @intCast(o.count))) : (n += 1) {
                for (self.obstacleBoxes(o)) |raw_b| {
                    const bb = scaleRect(raw_b, self.half);
                    const b: Rect = .{ .x = ox + n * step + bb.x, .y = oy + bb.y, .w = bb.w, .h = bb.h };
                    if (rectsOverlap(a, b)) return true;
                }
            }
        }
        return false;
    }

    // -- lifecycle ---------------------------------------------------------
    fn reset(self: *Game) void {
        self.pickScale();
        self.dino_y = 0;
        self.dino_vy = 0;
        self.on_ground = true;
        self.ducking = false;
        self.frame = 0;
        self.score = 0;
        self.score_f = 0;
        self.intro = 0;
        self.flashing = false;
        self.pending_beep = false;
        self.speed = self.baseSpeed();
        self.ground_scroll = 0;
        self.obstacles.clearRetainingCapacity();
        self.clouds.clearRetainingCapacity();
        self.dist_since_spawn = 0;
        self.next_spawn_dist = self.speed * 90;
        self.inverted = true;
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            self.spawnCloud(self.rng.random().intRangeAtMost(i32, 10, @max(11, self.width - 10)));
        }
        self.state = .idle;
    }

    fn startRun(self: *Game) void {
        self.state = .playing;
        self.frame = 0;
        self.speed = self.baseSpeed();
        self.intro = INTRO_FRAMES;
    }

    fn spawnCloud(self: *Game, at_x: i32) void {
        const top = 4;
        const bottom = @max(top + 1, self.groundPy() - self.dinoH() * 2);
        const y = self.rng.random().intRangeAtMost(i32, top, bottom);
        self.clouds.append(self.allocator, .{ .x = @floatFromInt(at_x), .y = y }) catch {};
    }

    fn spawnObstacle(self: *Game) void {
        const r = self.rng.random();
        const use_ptero = self.score > 450 and r.intRangeAtMost(u32, 0, 9) < 3;
        var o: Obstacle = .{ .x = @floatFromInt(self.width + 2), .kind = .cactus_small };
        if (use_ptero) {
            o.kind = .ptero;
            o.level = switch (r.intRangeAtMost(u32, 0, 2)) {
                0 => .low,
                1 => .mid,
                else => .high,
            };
        } else {
            const roll = r.intRangeAtMost(u32, 0, 99);
            if (roll < 45) {
                o.kind = .cactus_small;
                o.count = if (roll < 20) 1 else if (roll < 35) 2 else 3;
            } else {
                o.kind = .cactus_large;
                o.count = if (roll < 65) 1 else if (roll < 85) 2 else 3;
            }
        }
        self.obstacles.append(self.allocator, o) catch {};

        // Gap expressed in frames so reaction time stays constant as we speed
        // up, shrinking a little towards max speed like chrome does.
        const span = @max(0.001, self.maxSpeed() - self.baseSpeed());
        const t = std.math.clamp((self.speed - self.baseSpeed()) / span, 0, 1);
        const raw: f32 = @floatFromInt(r.intRangeAtMost(i32, 55, 110));
        const gap_frames = @max(44.0, raw * (1.0 - 0.32 * t));
        self.next_spawn_dist = self.speed * gap_frames;
        self.dist_since_spawn = 0;
    }

    fn update(self: *Game, want_jump: bool, duck_down: bool) void {
        self.frame += 1;
        if (self.frame % 20 == 0) self.blink = !self.blink;

        self.ducking = duck_down and self.on_ground;

        if (self.state == .idle) {
            self.ground_scroll += self.baseSpeed() * 0.5;
            self.moveClouds(self.baseSpeed() * 0.15);
            if (want_jump) self.startRun();
            return;
        }

        if (self.state == .game_over) return;

        // intro: the ground slides in and the dino runs on, nothing else yet
        if (self.intro > 0) {
            self.intro -= 1;
            self.ground_scroll += self.speed;
            self.moveClouds(self.speed * 0.15);
            return;
        }

        if (want_jump and self.on_ground and !self.ducking) {
            self.dino_vy = self.jumpVel();
            self.on_ground = false;
        }
        if (!self.on_ground and duck_down) {
            self.dino_vy += BASE_DROP_ACC * self.scale();
        }

        if (!self.on_ground) {
            self.dino_y += self.dino_vy;
            self.dino_vy += self.gravity();
            if (self.dino_y >= 0) {
                self.dino_y = 0;
                self.dino_vy = 0;
                self.on_ground = true;
            }
        }

        if (self.speed < self.maxSpeed()) {
            self.speed += self.baseSpeed() * ACCEL_RATIO;
        }

        // chrome counts round(distance * 0.025) in its own 44px-dino pixels;
        // normalising by widthScale keeps scores comparable across terminals
        const px_per_col = CHROME_DINO_W / @as(f32, @floatFromInt(self.dinoW()));
        const prev = self.score;
        self.score_f += self.speed * px_per_col / self.widthScale() * SCORE_PER_CHROME_PX;
        self.score = @intFromFloat(self.score_f);
        if (self.score > self.hi_score) self.hi_score = self.score;

        if (self.score / 100 != prev / 100 and self.score != 0) {
            self.flashing = true;
            self.flash_start = self.frame;
            self.pending_beep = true;
        }
        if (self.score / 700 != prev / 700 and self.score != 0) self.inverted = !self.inverted;
        if (self.flashing and self.frame - self.flash_start >= FLASH_PHASE_FRAMES * FLASH_PHASES) {
            self.flashing = false;
        }

        self.ground_scroll += self.speed;
        self.moveClouds(self.speed * 0.15);
        if (self.frame % 200 == 0 and self.clouds.items.len < 5) {
            self.spawnCloud(self.width + 2);
        }

        for (self.obstacles.items) |*o| o.x -= self.speed;
        var i: usize = 0;
        while (i < self.obstacles.items.len) {
            const o = self.obstacles.items[i];
            if (o.x + @as(f32, @floatFromInt(self.obstacleW(o))) < -2) {
                _ = self.obstacles.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        self.dist_since_spawn += self.speed;
        if (self.obstacles.items.len == 0 or self.dist_since_spawn >= self.next_spawn_dist) {
            self.spawnObstacle();
        }

        for (self.obstacles.items) |o| {
            if (self.collides(o)) {
                self.state = .game_over;
                break;
            }
        }
    }

    /// Chrome blinks the meter three times when you pass a hundred.
    fn scoreVisible(self: *Game) bool {
        if (!self.flashing) return true;
        return ((self.frame - self.flash_start) / FLASH_PHASE_FRAMES) % 2 == 0;
    }

    fn moveClouds(self: *Game, dx: f32) void {
        for (self.clouds.items) |*cl| {
            cl.x -= dx;
            if (cl.x < -@as(f32, @floatFromInt(artW(&CLOUD, self.half)))) {
                cl.x = @floatFromInt(self.width + 2);
                const top = 4;
                const bottom = @max(top + 1, self.groundPy() - self.dinoH() * 2);
                cl.y = self.rng.random().intRangeAtMost(i32, top, bottom);
            }
        }
    }

    // -- pixel canvas ------------------------------------------------------
    fn ensureCanvas(self: *Game) !void {
        const w = self.width;
        const h = self.height * 2;
        if (self.px_w == w and self.px_h == h and self.px.len != 0) return;
        if (self.px.len != 0) self.allocator.free(self.px);
        self.px = try self.allocator.alloc(u8, @intCast(@max(1, w * h)));
        self.px_w = w;
        self.px_h = h;
    }

    fn clearCanvas(self: *Game) void {
        @memset(self.px, 0);
    }

    fn setPx(self: *Game, x: i32, y: i32, color: u8) void {
        if (x < 0 or y < 0 or x >= self.px_w or y >= self.px_h) return;
        self.px[@intCast(y * self.px_w + x)] = color;
    }

    fn getPx(self: *Game, x: i32, y: i32) u8 {
        if (x < 0 or y < 0 or x >= self.px_w or y >= self.px_h) return 0;
        return self.px[@intCast(y * self.px_w + x)];
    }

    fn blit(self: *Game, art: Art, x0: i32, y0: i32, color: u8) void {
        const w = artW(art, self.half);
        const h = artH(art, self.half);
        if (x0 + w < 0 or x0 >= self.px_w) return;
        var y: i32 = 0;
        while (y < h) : (y += 1) {
            const py = y0 + y;
            if (py < 0 or py >= self.px_h) continue;
            var x: i32 = 0;
            while (x < w) : (x += 1) {
                if (artPixel(art, x, y, self.half)) self.setPx(x0 + x, py, color);
            }
        }
    }
};

fn rectsOverlap(a: Rect, b: Rect) bool {
    return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y;
}

// ---------------------------------------------------------------------------
// Terminal helpers
// ---------------------------------------------------------------------------
const STDIN_FD: posix.fd_t = 0;
const STDOUT_FD: posix.fd_t = 1;

fn nowNs() i128 {
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * 1000000000 + @as(i128, ts.nsec);
}

fn getWinsize() struct { rows: i32, cols: i32 } {
    var wsz: posix.winsize = .{ .row = 24, .col = 80, .xpixel = 0, .ypixel = 0 };
    const rc = c.ioctl(STDOUT_FD, c.T.IOCGWINSZ, @intFromPtr(&wsz));
    if (rc == 0 and wsz.col != 0 and wsz.row != 0) {
        return .{ .rows = @intCast(wsz.row), .cols = @intCast(wsz.col) };
    }
    const rc2 = c.ioctl(STDIN_FD, c.T.IOCGWINSZ, @intFromPtr(&wsz));
    if (rc2 == 0 and wsz.col != 0 and wsz.row != 0) {
        return .{ .rows = @intCast(wsz.row), .cols = @intCast(wsz.col) };
    }
    return .{ .rows = 24, .cols = 80 };
}

fn enableRawMode() !posix.termios {
    const orig = try posix.tcgetattr(STDIN_FD);
    var raw = orig;

    raw.iflag.BRKINT = false;
    raw.iflag.ICRNL = false;
    raw.iflag.IGNBRK = false;
    raw.iflag.IGNCR = false;
    raw.iflag.INLCR = false;
    raw.iflag.IXON = false;
    raw.iflag.IXOFF = false;
    raw.iflag.IXANY = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.INPCK = false;
    raw.iflag.PARMRK = false;

    raw.oflag.OPOST = false;
    raw.cflag.CSIZE = .CS8;

    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    raw.cc[16] = 0; // VMIN
    raw.cc[17] = 1; // VTIME

    try posix.tcsetattr(STDIN_FD, .NOW, raw);
    return orig;
}

fn disableRawMode(orig: posix.termios) void {
    posix.tcsetattr(STDIN_FD, .NOW, orig) catch {};
}

fn writeAll(fd: posix.fd_t, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n: usize = @intCast(c.write(fd, bytes[off..].ptr, bytes[off..].len));
        if (n == 0) break;
        if (@as(isize, @bitCast(n)) < 0) break;
        off += n;
    }
}

fn hideCursor(buf: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
    try buf.appendSlice(alloc, "\x1b[?25l");
}
fn showCursor(buf: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
    try buf.appendSlice(alloc, "\x1b[?25h");
}
fn enterAlt(buf: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
    try buf.appendSlice(alloc, "\x1b[?1049h");
}
fn leaveAlt(buf: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
    try buf.appendSlice(alloc, "\x1b[?1049l");
}
fn clearScreen(buf: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
    try buf.appendSlice(alloc, "\x1b[2J\x1b[H");
}
fn moveTo(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, row: i32, col: i32) !void {
    try buf.print(alloc, "\x1b[{d};{d}H", .{ row + 1, col + 1 });
}

// ---------------------------------------------------------------------------
// Input
//
// A terminal reports no key-up events, so "is the duck key still held?" has to
// be inferred from the keyboard's auto-repeat. The naive version - duck for a
// few frames per keypress - stutters, because the terminal waits ~600ms before
// the first repeat: duck, stand, duck.
//
// So the hold window is adaptive. The first press holds long enough to bridge
// that delay; once repeats are actually arriving the window shrinks, so letting
// go feels immediate. A release event is honoured if one ever shows up, but
// nothing depends on it.
// ---------------------------------------------------------------------------

const DUCK_FIRST_MS: i128 = 800;
const DUCK_REPEAT_MS: i128 = 200;

// sentinels for keys that are not unicode code points
const KEY_UP: u32 = 0xE000;
const KEY_DOWN: u32 = 0xE001;

const Input = struct {
    jump: bool = false,
    quit: bool = false,
    restart: bool = false,
};

const InputState = struct {
    duck_held: bool = false,
    duck_expire: i128 = 0,
};

fn isCsiFinal(b: u8) bool {
    return b >= 0x40 and b <= 0x7e;
}

fn parseU32(s: []const u8) u32 {
    return std.fmt.parseInt(u32, s, 10) catch 0;
}

fn isDuckKey(code: u32) bool {
    return code == KEY_DOWN or code == 's' or code == 'S' or code == 'j' or code == 'J';
}

fn isJumpKey(code: u32) bool {
    return code == KEY_UP or code == ' ' or code == 'w' or code == 'W' or code == 'k' or code == 'K';
}

fn handleKey(st: *InputState, inp: *Input, code: u32, event: u32) void {
    const released = event == 3;

    if (isDuckKey(code)) {
        if (released) {
            st.duck_held = false;
        } else {
            const window: i128 = if (st.duck_held) DUCK_REPEAT_MS else DUCK_FIRST_MS;
            st.duck_held = true;
            st.duck_expire = nowNs() + window * 1_000_000;
        }
        return;
    }

    if (released) return;

    // any other key means the duck key is not the one being held
    st.duck_held = false;

    if (isJumpKey(code)) {
        inp.jump = true;
    } else if (code == '\r' or code == '\n') {
        inp.jump = true;
        inp.restart = true;
    } else if (code == 'q' or code == 'Q' or code == 3) {
        inp.quit = true;
    } else if (code == 'r' or code == 'R') {
        inp.restart = true;
    }
}

fn handleCsi(st: *InputState, inp: *Input, params: []const u8, final: u8) void {
    if (params.len != 0 and (params[0] == '?' or params[0] == '>' or params[0] == '<')) return;

    // "<key>;<mods>:<event>" - the event type, when present, is a sub-parameter
    var event: u32 = 1;
    var key: u32 = 0;
    var parts = std.mem.splitScalar(u8, params, ';');
    if (parts.next()) |p0| {
        var subs = std.mem.splitScalar(u8, p0, ':');
        key = parseU32(subs.next() orelse "");
    }
    if (parts.next()) |p1| {
        var subs = std.mem.splitScalar(u8, p1, ':');
        _ = subs.next();
        if (subs.next()) |ev| event = parseU32(ev);
    }

    switch (final) {
        'A' => handleKey(st, inp, KEY_UP, event),
        'B' => handleKey(st, inp, KEY_DOWN, event),
        'u' => handleKey(st, inp, key, event),
        else => {},
    }
}

fn pollInput(st: *InputState) Input {
    var inp = Input{};
    var fds = [_]posix.pollfd{.{ .fd = STDIN_FD, .events = posix.POLL.IN, .revents = 0 }};
    const n = posix.poll(&fds, 0) catch 0;

    if (n != 0 and fds[0].revents & posix.POLL.IN != 0) {
        var buf: [128]u8 = undefined;
        const read_n = posix.read(STDIN_FD, &buf) catch 0;
        var i: usize = 0;
        while (i < read_n) {
            const ch = buf[i];
            if (ch == 0x1b and i + 1 < read_n and buf[i + 1] == '[') {
                var j = i + 2;
                while (j < read_n and !isCsiFinal(buf[j])) : (j += 1) {}
                if (j >= read_n) break; // truncated sequence, drop the tail
                handleCsi(st, &inp, buf[i + 2 .. j], buf[j]);
                i = j + 1;
                continue;
            }
            // a lone ESC quits, but only when it is the whole read - otherwise
            // it is the head of an escape sequence split across reads
            if (ch == 0x1b and read_n == 1) {
                inp.quit = true;
                i += 1;
                continue;
            }
            handleKey(st, &inp, ch, 1);
            i += 1;
        }
    }

    if (st.duck_held and nowNs() > st.duck_expire) st.duck_held = false;
    return inp;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
/// Chrome paints its own canvas, so day is light with dark sprites and the
/// night flip inverts both. Painting the background is what makes the flip
/// visible at all - sprite colours alone do nothing on a dark terminal.
fn bgCode(inverted: bool) []const u8 {
    return if (inverted) "\x1b[48;5;233m" else "\x1b[48;5;255m";
}

fn colorCode(id: u8, inverted: bool) []const u8 {
    if (inverted) return switch (id) {
        C_CACTUS => "\x1b[38;5;108m",
        C_CLOUD => "\x1b[38;5;240m",
        else => "\x1b[38;5;253m",
    };
    return switch (id) {
        C_DINO => "\x1b[38;5;240m", // chrome's #535353
        C_CACTUS => "\x1b[38;5;65m",
        C_CLOUD => "\x1b[38;5;249m",
        C_GROUND => "\x1b[38;5;240m",
        else => "\x1b[38;5;240m",
    };
}

/// Draw the whole world into the pixel canvas.
fn compose(game: *Game) void {
    game.clearCanvas();

    const gpy = game.groundPy();

    // clouds
    for (game.clouds.items) |cl| {
        const cx: i32 = @intFromFloat(@round(cl.x));
        game.blit(&CLOUD, cx, cl.y, C_CLOUD);
    }

    // ground: one solid line plus chrome's scattered pebbles
    {
        const scroll: i32 = @intFromFloat(@floor(game.ground_scroll));
        const ground_w = game.introGroundW();
        var x: i32 = 0;
        while (x < ground_w) : (x += 1) {
            game.setPx(x, gpy, C_GROUND);
            const p = @mod(x + scroll, 43);
            if (p == 0 or p == 1) game.setPx(x, gpy - 1, C_GROUND);
            const q = @mod(x + scroll, 97);
            if (q == 0) game.setPx(x, gpy + 1, C_GROUND);
        }
    }

    // obstacles
    for (game.obstacles.items) |o| {
        const art = game.obstacleArt(o);
        const ox: i32 = @intFromFloat(@round(o.x));
        const oy = game.obstacleTopPy(o);
        const step = artW(art, game.half) + game.cactusGap();
        var n: i32 = 0;
        while (n < @as(i32, @intCast(o.count))) : (n += 1) {
            game.blit(art, ox + n * step, oy, C_CACTUS);
        }
    }

    // dino
    {
        const art = game.dinoArt();
        game.blit(art, game.dinoX(), game.dinoTopPy(art), C_DINO);
    }

    // chrome's restart button, on the game over screen
    if (game.state == .game_over) {
        const iw = artW(&RESTART, game.half);
        const ix = @divFloor(game.width - iw, 2);
        const iy = (@divFloor(game.height, 2) - 3) * 2; // sits above the dino
        game.blit(&RESTART, ix, iy, C_DINO);
    }
}

/// Flush the pixel canvas as half-block characters.
fn emit(game: *Game, buf: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
    const bg = bgCode(game.inverted);
    var cur: u8 = 0;
    var r: i32 = 0;
    while (r < game.height) : (r += 1) {
        const top_y = r * 2;
        const bot_y = r * 2 + 1;
        var last: i32 = -1;
        var x: i32 = 0;
        while (x < game.width) : (x += 1) {
            if (game.getPx(x, top_y) != 0 or game.getPx(x, bot_y) != 0) last = x;
        }
        try moveTo(buf, alloc, r, 0);
        try buf.appendSlice(alloc, bg);
        cur = 0;
        x = 0;
        while (x <= last) : (x += 1) {
            const t = game.getPx(x, top_y);
            const b = game.getPx(x, bot_y);
            if (t == 0 and b == 0) {
                try buf.append(alloc, ' ');
                continue;
            }
            const col: u8 = if (t != 0) t else b;
            if (col != cur) {
                try buf.appendSlice(alloc, colorCode(col, game.inverted));
                cur = col;
            }
            if (t != 0 and b != 0) {
                try buf.appendSlice(alloc, "\u{2588}");
            } else if (t != 0) {
                try buf.appendSlice(alloc, "\u{2580}");
            } else {
                try buf.appendSlice(alloc, "\u{2584}");
            }
        }
        // erase-to-end fills with the background we just set
        try buf.appendSlice(alloc, "\x1b[K");
    }
}

fn render(game: *Game, buf: *std.ArrayList(u8)) !void {
    const alloc = game.allocator;
    buf.clearRetainingCapacity();
    try buf.appendSlice(alloc, "\x1b[H");

    const w = game.width;
    const h = game.height;

    const bg = bgCode(game.inverted);
    const ink = colorCode(C_DINO, game.inverted);
    const faint = if (game.inverted) "\x1b[38;5;242m" else "\x1b[38;5;248m";
    const reset = "\x1b[0m";

    if (w < 40 or h < 14) {
        try clearScreen(buf, alloc);
        const msg = " TERMINAL TOO SMALL - enlarge to play ";
        const row = @divFloor(h, 2);
        const col = @max(0, @divFloor(w - @as(i32, @intCast(msg.len)), 2));
        try moveTo(buf, alloc, row, col);
        try buf.appendSlice(alloc, msg);
        return;
    }

    try game.ensureCanvas();
    compose(game);
    try emit(game, buf, alloc);

    // every overlay repaints the background, otherwise it punches a hole in the
    // canvas with the terminal's own colours
    const label = struct {
        fn at(b: *std.ArrayList(u8), a: std.mem.Allocator, bgc: []const u8, fgc: []const u8, row: i32, col: i32, text: []const u8) !void {
            try moveTo(b, a, row, @max(0, col));
            try b.appendSlice(a, bgc);
            try b.appendSlice(a, fgc);
            try b.appendSlice(a, text);
        }
        fn centered(b: *std.ArrayList(u8), a: std.mem.Allocator, bgc: []const u8, fgc: []const u8, row: i32, width: i32, text: []const u8) !void {
            const col = @divFloor(width - @as(i32, @intCast(text.len)), 2);
            try at(b, a, bgc, fgc, row, col, text);
        }
    };

    // ---- score header (top right), blinking on every hundred ----
    {
        var score_buf: [32]u8 = undefined;
        var hi_buf: [32]u8 = undefined;
        const score_str = try std.fmt.bufPrint(&score_buf, "{d:0>5}", .{game.score});
        const hi_str = try std.fmt.bufPrint(&hi_buf, "HI {d:0>5}", .{game.hi_score});

        const col = w - @as(i32, @intCast(hi_str.len + score_str.len)) - 4;
        try label.at(buf, alloc, bg, faint, 0, col, hi_str);
        if (game.scoreVisible()) {
            try label.at(buf, alloc, bg, ink, 0, col + @as(i32, @intCast(hi_str.len)) + 2, score_str);
        }
    }

    // ---- UI overlays ----
    if (game.state == .idle) {
        try label.centered(buf, alloc, bg, ink, 2, w, " CHROME DINO ");
        if (game.blink) {
            try label.centered(buf, alloc, bg, ink, @divFloor(h, 2) + 2, w, "Press SPACE / UP to start");
        }
        try label.centered(buf, alloc, bg, faint, @divFloor(h, 2) + 3, w, "DOWN to duck  |  Q to quit");
    } else if (game.state == .game_over) {
        const mid = @divFloor(h, 2);
        try label.centered(buf, alloc, bg, ink, @max(0, mid - 6), w, "G A M E   O V E R");

        var sc_buf: [64]u8 = undefined;
        const sc = try std.fmt.bufPrint(&sc_buf, "{d:0>5}   HI {d:0>5}", .{ game.score, game.hi_score });
        try label.centered(buf, alloc, bg, faint, @max(1, mid - 4), w, sc);

        // the restart icon itself is drawn into the canvas by compose(); the
        // hint goes to the footer so nothing sits on top of the playfield
        try label.at(buf, alloc, bg, faint, h - 1, 1, "SPACE or R to restart   Q to quit");
    }

    if (game.state == .playing and w > 44) {
        const footer = "SPACE/UP jump   DOWN duck   Q quit";
        try label.at(buf, alloc, bg, faint, h - 1, w - @as(i32, @intCast(footer.len)) - 1, footer);
    }

    try buf.appendSlice(alloc, reset);
    try moveTo(buf, alloc, h - 1, 0);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
/// `DINO_KEYS=1 dino`: dump what the terminal actually sends, with timings. Exists
/// because "the duck key sticks" can only be explained by the terminal, and
/// that is invisible from inside the game loop.
fn dumpKeys() !void {
    const orig = enableRawMode() catch |e| {
        std.debug.print("failed to enable raw mode: {any}\n", .{e});
        return;
    };
    defer disableRawMode(orig);

    var out: [4096]u8 = undefined;
    const banner = "key dump - press keys (hold the duck key too), q to quit\r\n\r\n";
    writeAll(STDOUT_FD, banner);

    const start = nowNs();
    while (true) {
        var fds = [_]posix.pollfd{.{ .fd = STDIN_FD, .events = posix.POLL.IN, .revents = 0 }};
        const n = posix.poll(&fds, 5000) catch 0;
        if (n == 0) continue;

        var buf: [128]u8 = undefined;
        const read_n = posix.read(STDIN_FD, &buf) catch 0;
        if (read_n == 0) continue;

        const ms = @divTrunc(nowNs() - start, 1_000_000);
        var w: usize = 0;
        var line = try std.fmt.bufPrint(out[w..], "{d:>6}ms  {d:>2} bytes  ", .{ ms, read_n });
        w += line.len;
        for (buf[0..read_n]) |b| {
            line = if (b == 0x1b)
                try std.fmt.bufPrint(out[w..], "ESC ", .{})
            else if (b >= 0x20 and b < 0x7f)
                try std.fmt.bufPrint(out[w..], "{c} ", .{b})
            else
                try std.fmt.bufPrint(out[w..], "\\x{x:0>2} ", .{b});
            w += line.len;
        }
        line = try std.fmt.bufPrint(out[w..], "\r\n", .{});
        w += line.len;
        writeAll(STDOUT_FD, out[0..w]);

        if (std.mem.indexOfScalar(u8, buf[0..read_n], 'q') != null) break;
    }
    writeAll(STDOUT_FD, "\r\n");
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    if (c.getenv("DINO_KEYS") != null) return dumpKeys();

    const is_tty = c.isatty(STDIN_FD) != 0;
    if (!is_tty) {
        std.debug.print("Not a TTY. Please run in a terminal.\n", .{});
        return;
    }

    var ws = getWinsize();
    var game = Game.init(alloc, ws.cols, ws.rows);
    defer game.deinit();
    game.reset();

    const orig = enableRawMode() catch |e| {
        std.debug.print("failed to enable raw mode: {any}\n", .{e});
        return;
    };
    defer disableRawMode(orig);

    var input_state: InputState = .{};

    var tmp_buf: std.ArrayList(u8) = .empty;
    defer tmp_buf.deinit(alloc);

    tmp_buf.clearRetainingCapacity();
    try enterAlt(&tmp_buf, alloc);
    try hideCursor(&tmp_buf, alloc);
    try tmp_buf.appendSlice(alloc, "\x1b[2J\x1b[H");
    writeAll(STDOUT_FD, tmp_buf.items);

    defer {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(alloc);
        out.appendSlice(alloc, "\x1b[0m") catch {};
        showCursor(&out, alloc) catch {};
        leaveAlt(&out, alloc) catch {};
        writeAll(STDOUT_FD, out.items);
        disableRawMode(orig);
    }

    var frame_buf: std.ArrayList(u8) = .empty;
    defer frame_buf.deinit(alloc);

    var last_time: i128 = nowNs();
    var acc: i128 = 0;

    var running = true;
    var was_over = false;
    while (running) {
        const now: i128 = nowNs();
        var delta: i128 = now - last_time;
        last_time = now;
        if (delta > 100_000_000) delta = 100_000_000;
        if (delta < 0) delta = 0;
        acc += delta;

        const inp = pollInput(&input_state);
        var jump = inp.jump;

        if (inp.quit) {
            running = false;
            break;
        }

        if (game.state == .game_over and (jump or inp.restart)) {
            const hi = game.hi_score;
            game.reset();
            game.hi_score = hi;
            game.startRun();
            jump = false;
        }

        if (game.frame % 30 == 0) {
            ws = getWinsize();
            if (ws.cols != game.width or ws.rows != game.height) {
                game.width = ws.cols;
                game.height = ws.rows;
                game.pickScale();
                writeAll(STDOUT_FD, "\x1b[2J");
            }
        }

        while (acc >= FRAME_NS) : (acc -= FRAME_NS) {
            game.update(jump, input_state.duck_held);
            jump = false;
        }

        try render(&game, &frame_buf);
        writeAll(STDOUT_FD, frame_buf.items);

        const after_render: i128 = nowNs();
        const elapsed = after_render - now;
        const target: i128 = @intCast(FRAME_NS);
        if (elapsed < target) {
            const sleep_ns: u64 = @intCast(target - elapsed);
            var ts: c.timespec = .{ .sec = @intCast(sleep_ns / 1000000000), .nsec = @intCast(sleep_ns % 1000000000) };
            _ = c.nanosleep(&ts, null);
        }

        // chrome plays the death sound once, and one blip per hundred points
        const is_over = game.state == .game_over;
        if (is_over and !was_over) writeAll(STDOUT_FD, "\x07");
        was_over = is_over;
        if (game.pending_beep) {
            game.pending_beep = false;
            writeAll(STDOUT_FD, "\x07");
        }
    }
}
