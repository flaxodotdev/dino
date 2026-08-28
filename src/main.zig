const std = @import("std");
const posix = std.posix;
const c = std.c;

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const FPS: u64 = 60;
const FRAME_NS: u64 = 1_000_000_000 / FPS;
const DINO_X: i32 = 6; // fixed column where dino lives

const GRAVITY: f32 = 0.12;
const JUMP_VEL: f32 = -1.35;
const DROP_VEL: f32 = 5.0;
const INITIAL_SPEED: f32 = 1.5;
const MAX_SPEED: f32 = 5.2;
const SPEED_INC: f32 = 0.00065;
const GROUND_OFFSET_Y: i32 = 2; // ground is height-2

// Dino physics
const DINO_GROUND_OFFSET: i32 = 4; // height of standing dino
const DINO_DUCK_HEIGHT: i32 = 2;
const DINO_WIDTH: i32 = 7;
const DINO_HEIGHT: i32 = 4;

// ---------------------------------------------------------------------------
// Sprites (chrome-authentic ascii approximation)
// Using block characters – looks great in modern terminals
// ---------------------------------------------------------------------------

// running frame A (legs spread)
const DINO_RUN_A = [_][]const u8{
    " ██████ ",
    " ██████▄",
    " ██████ ",
    "  ▀  ▀  ",
};

// running frame B (legs together other phase)
const DINO_RUN_B = [_][]const u8{
    " ██████ ",
    " ██████▄",
    " ██████ ",
    "  ▀▄ ▀▄ ",
};

const DINO_JUMP = [_][]const u8{
    " ██████ ",
    " ██████▄",
    " ██████ ",
    "  ▀  ▀  ",
};

const DINO_DUCK_A = [_][]const u8{
    "   ██████▄ ",
    " █████████ ",
    "   ▀  ▀ ▀▄ ",
};

const DINO_DUCK_B = [_][]const u8{
    "   ██████▄ ",
    " █████████ ",
    "   ▀▄ ▀  ▀ ",
};

const DINO_DEAD = [_][]const u8{
    " ██████ ",
    " ████×█▄",
    " ██████ ",
    "  ▀  ▀  ",
};

// cactus sprites – small and large variants (like chrome)
const CACTUS_SMALL_SINGLE = [_][]const u8{
    " █ ",
    " █ ",
    "███",
};

const CACTUS_SMALL_DOUBLE = [_][]const u8{
    " █  █ ",
    " █  █ ",
    "██████",
};

const CACTUS_SMALL_TRIPLE = [_][]const u8{
    " █  █  █ ",
    " █  █  █ ",
    "█████████",
};

const CACTUS_LARGE_SINGLE = [_][]const u8{
    "  █  ",
    "  █  ",
    "  █  ",
    "█████",
};

const CACTUS_LARGE_DOUBLE = [_][]const u8{
    "  █    █  ",
    "  █    █  ",
    "  █    █  ",
    "██████████",
};

const CACTUS_LARGE_TRIPLE = [_][]const u8{
    "  █    █    █  ",
    "  █    █    █  ",
    "  █    █    █  ",
    "███████████████",
};

// pterodactyl (chrome bird) – 2 frames of wing flap
const PTERO_A = [_][]const u8{
    "  ▄▄▄  ",
    " █▄█▄█ ",
};

const PTERO_B = [_][]const u8{
    "  ▀█▀  ",
    " █▄█▄█ ",
};

// clouds
const CLOUD = "☁☁☁";

// ground pattern
const GROUND_CHAR = "─";
const GROUND_BUMP = "▁";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
const ObstacleKind = enum {
    cactus_small_single,
    cactus_small_double,
    cactus_small_triple,
    cactus_large_single,
    cactus_large_double,
    cactus_large_triple,
    ptero_low,
    ptero_mid,
    ptero_high,
};

const Obstacle = struct {
    x: f32,
    y: i32, // y offset from top (will be computed from ground)
    kind: ObstacleKind,
    w: i32,
    h: i32,
};

const Cloud = struct {
    x: f32,
    y: i32,
};

const GameState = enum { idle, playing, game_over };

const Game = struct {
    width: i32,
    height: i32,
    state: GameState = .idle,
    dino_y: f32 = 0, // 0 = on ground, negative = in air (pixels up)
    dino_vy: f32 = 0,
    on_ground: bool = true,
    ducking: bool = false,
    duck_timer: i32 = 0,
    frame: u64 = 0,
    score: u32 = 0,
    hi_score: u32 = 0,
    speed: f32 = INITIAL_SPEED,
    ground_scroll: f32 = 0,
    allocator: std.mem.Allocator,
    obstacles: std.ArrayList(Obstacle),
    clouds: std.ArrayList(Cloud),
    next_spawn_dist: f32 = 40,
    dist_since_spawn: f32 = 0,
    blink: bool = false,
    rng: std.Random.DefaultPrng,
    inverted: bool = false, // day/nigh like chrome

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
    }

    fn reset(self: *Game) void {
        self.dino_y = 0;
        self.dino_vy = 0;
        self.on_ground = true;
        self.ducking = false;
        self.duck_timer = 0;
        self.frame = 0;
        self.score = 0;
        self.speed = INITIAL_SPEED;
        self.ground_scroll = 0;
        self.obstacles.clearRetainingCapacity();
        self.clouds.clearRetainingCapacity();
        self.dist_since_spawn = 0;
        self.next_spawn_dist = 55;
        self.inverted = false;
        // seed some clouds
        self.clouds.clearRetainingCapacity();
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const cx: f32 = @floatFromInt(self.rng.random().intRangeAtMost(i32, 10, self.width - 10));
            const cy: i32 = self.rng.random().intRangeAtMost(i32, 2, 6);
            self.clouds.append(self.allocator, .{ .x = cx, .y = cy }) catch {};
        }
        self.state = .idle;
    }

    fn groundY(self: *Game) i32 {
        return self.height - GROUND_OFFSET_Y;
    }

    fn dinoTopY(self: *Game) i32 {
        // dino_y is negative when jumping, 0 on ground. Convert to screen y.
        const gy = self.groundY();
        if (self.ducking and self.on_ground) {
            // ducking height is 2 + 1 padding
            const h = DINO_DUCK_HEIGHT + 1;
            const y = gy - h + 1;
            return y;
        } else {
            const h = DINO_HEIGHT;
            const base = gy - h + 1;
            return base + @as(i32, @intFromFloat(@floor(self.dino_y)));
        }
    }

    fn dinoHitbox(self: *Game) struct { x: i32, y: i32, w: i32, h: i32 } {
        const ty = self.dinoTopY();
        if (self.ducking and self.on_ground) {
            // duck is wider, lower, tighter box
            return .{ .x = DINO_X + 1, .y = ty + 1, .w = 8, .h = 2 };
        } else {
            // standing/jumping – trim 1 pixel from left/right for fairness like chrome
            return .{ .x = DINO_X + 1, .y = ty + 1, .w = 5, .h = 3 };
        }
    }

    fn obstacleHitbox(o: Obstacle, gy: i32) struct { x: i32, y: i32, w: i32, h: i32 } {
        const ox: i32 = @intFromFloat(@round(o.x));
        // y is precomputed as ground-relative
        // For cactus: sits on ground, top = gy - h +1
        // For ptero: y is absolute
        var oy: i32 = undefined;
        switch (o.kind) {
            .ptero_low, .ptero_mid, .ptero_high => oy = o.y,
            else => oy = gy - o.h + 1,
        }
        // shrink hitbox slightly like chrome (1px inset)
        return .{ .x = ox + 1, .y = oy + 1, .w = @max(1, o.w - 2), .h = @max(1, o.h - 1) };
    }

    fn spawnObstacle(self: *Game) void {
        const r = self.rng.random();
        // after 500 points, start spawning pteros 30% chance
        const use_ptero = self.score > 500 and r.intRangeAtMost(u32, 0, 9) < 3;
        var kind: ObstacleKind = undefined;
        var w: i32 = 3;
        var h: i32 = 3;
        var y: i32 = 0;
        const gy = self.groundY();
        if (use_ptero) {
            const sel = r.intRangeAtMost(u32, 0, 2);
            switch (sel) {
                0 => {
                    kind = .ptero_low;
                    w = 7;
                    h = 2;
                    y = gy - 2; // just above ground
                },
                1 => {
                    kind = .ptero_mid;
                    w = 7;
                    h = 2;
                    y = gy - 5;
                },
                else => {
                    kind = .ptero_high;
                    w = 7;
                    h = 2;
                    y = gy - 7;
                },
            }
            // duck-required ptero height: if speed high, more mid/high
        } else {
            // cactus variants weighted like chrome
            const roll = r.intRangeAtMost(u32, 0, 99);
            if (roll < 20) {
                kind = .cactus_small_single;
                w = 3;
                h = 3;
            } else if (roll < 35) {
                kind = .cactus_small_double;
                w = 6;
                h = 3;
            } else if (roll < 45) {
                kind = .cactus_small_triple;
                w = 9;
                h = 3;
            } else if (roll < 65) {
                kind = .cactus_large_single;
                w = 5;
                h = 4;
            } else if (roll < 85) {
                kind = .cactus_large_double;
                w = 10;
                h = 4;
            } else {
                kind = .cactus_large_triple;
                w = 15;
                h = 4;
            }
            y = gy - h + 1;
        }
        self.obstacles.append(self.allocator, .{ .x = @floatFromInt(self.width + 2), .y = y, .kind = kind, .w = w, .h = h }) catch {};
        // next distance scales fairly with speed – keeps reaction time ~constant
        // base 42-60 + speed*4.5  => at 1.5: 49 +6.7=~56 cols (~37 frames, 0.61s), at 5.2: 49+23=72 cols (~14 frames, 0.23s)
        const base: f32 = @floatFromInt(r.intRangeAtMost(i32, 42, 60));
        self.next_spawn_dist = base + self.speed * 4.5;
        self.dist_since_spawn = 0;
    }

    fn update(self: *Game, want_jump: bool, want_duck: bool, want_duck_hold: bool) void {
        self.frame += 1;
        // blink for idle
        if (self.frame % 20 == 0) self.blink = !self.blink;

        // handle duck timer for hold behavior (terminal has no keyup)
        if (want_duck) self.duck_timer = 8;
        if (self.duck_timer > 0) {
            self.duck_timer -= 1;
            self.ducking = want_duck_hold or self.duck_timer > 4;
            // also consider immediate press
            if (want_duck) self.ducking = true;
        } else {
            self.ducking = false;
        }
        // if jumping and ducking, cancel duck
        if (!self.on_ground) self.ducking = false;

        if (self.state == .idle) {
            // ground still scrolls idle like chrome shows static? We'll scroll a little
            self.ground_scroll += self.speed * 0.5;
            if (self.ground_scroll >= 20) self.ground_scroll -= 20;
            // update clouds idle
            for (self.clouds.items) |*cl| {
                cl.x -= 0.3;
                if (cl.x < -5) {
                    cl.x = @floatFromInt(self.width + 2);
                    cl.y = self.rng.random().intRangeAtMost(i32, 2, 6);
                }
            }
            if (want_jump) {
                self.state = .playing;
                self.frame = 0;
                // beep start
            }
            return;
        }

        if (self.state == .game_over) {
            return;
        }

        // playing update
        // jump input
        if (want_jump and self.on_ground and !self.ducking) {
            self.dino_vy = JUMP_VEL;
            self.on_ground = false;
        }
        // duck while in air = fast drop (chrome drop)
        if (!self.on_ground and want_duck) {
            self.dino_vy += DROP_VEL * 0.12;
        }

        // physics
        if (!self.on_ground) {
            self.dino_y += self.dino_vy;
            self.dino_vy += GRAVITY;
            if (self.dino_y >= 0) {
                self.dino_y = 0;
                self.dino_vy = 0;
                self.on_ground = true;
            }
        } else {
            // keep duck state while hold
        }

        // speed ramp
        if (self.speed < MAX_SPEED) {
            self.speed += SPEED_INC;
        }

        // score
        self.score += 1;
        if (self.score > self.hi_score) self.hi_score = self.score;
        // like chrome, every 100 points flash and invert every 700
        if (self.score % 700 == 0 and self.score != 0) {
            self.inverted = !self.inverted;
        }

        // ground scroll
        self.ground_scroll += self.speed;
        if (self.ground_scroll >= 40) self.ground_scroll -= 40;

        // clouds
        for (self.clouds.items) |*cl| {
            cl.x -= self.speed * 0.15;
            if (cl.x < -6) {
                cl.x = @floatFromInt(self.width + 5);
                cl.y = self.rng.random().intRangeAtMost(i32, 2, 6);
            }
        }
        // occasionally add cloud
        if (self.frame % 200 == 0 and self.clouds.items.len < 5) {
            self.clouds.append(self.allocator, .{ .x = @floatFromInt(self.width + 2), .y = self.rng.random().intRangeAtMost(i32, 2, 6) }) catch {};
        }

        // obstacles movement
        for (self.obstacles.items) |*o| {
            o.x -= self.speed;
            // ptero animated wing via frame? keep y bubble for low pteros? Add slight bob?
            if (o.kind == .ptero_low or o.kind == .ptero_mid or o.kind == .ptero_high) {
                // subtle up/down float
                // do nothing – wing flap is visual only
            }
        }
        // remove offscreen
        var i: usize = 0;
        while (i < self.obstacles.items.len) {
            if (self.obstacles.items[i].x + @as(f32, @floatFromInt(self.obstacles.items[i].w)) < -2) {
                _ = self.obstacles.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        // spawn logic
        self.dist_since_spawn += self.speed;
        if (self.obstacles.items.len == 0 or self.dist_since_spawn >= self.next_spawn_dist) {
            // also ensure not too crowded: last obstacle far enough
            if (self.obstacles.items.len == 0) {
                self.spawnObstacle();
            } else {
                const last = self.obstacles.items[self.obstacles.items.len - 1];
                if (last.x < @as(f32, @floatFromInt(self.width)) - self.next_spawn_dist) {
                    self.spawnObstacle();
                } else if (self.dist_since_spawn > self.next_spawn_dist + 40) {
                    // force spawn if waited too long
                    self.spawnObstacle();
                }
            }
        }

        // collision
        const dbox = self.dinoHitbox();
        const gy = self.groundY();
        for (self.obstacles.items) |o| {
            const obox = obstacleHitbox(o, gy);
            if (boxesOverlap(dbox, obox)) {
                self.state = .game_over;
                // store hi
                break;
            }
        }
    }
};

fn boxesOverlap(a: anytype, b: anytype) bool {
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
    // try stdin
    const rc2 = c.ioctl(STDIN_FD, c.T.IOCGWINSZ, @intFromPtr(&wsz));
    if (rc2 == 0 and wsz.col != 0 and wsz.row != 0) {
        return .{ .rows = @intCast(wsz.row), .cols = @intCast(wsz.col) };
    }
    return .{ .rows = 24, .cols = 80 };
}

fn enableRawMode() !posix.termios {
    const orig = try posix.tcgetattr(STDIN_FD);
    var raw = orig;

    // input flags – turn off all the cooking
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

    // output flags
    raw.oflag.OPOST = false;

    // control flags – 8 bit
    raw.cflag.CSIZE = .CS8;

    // local flags
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    // cc – VMIN / VTIME for non-blocking read via poll
    // on macos NCCS 20, VMIN is index 16, VTIME 17
    raw.cc[16] = 0; // VMIN
    raw.cc[17] = 1; // VTIME (1 = 100ms, but we poll anyway)
    // alternative: both 0 for immediate

    try posix.tcsetattr(STDIN_FD, .NOW, raw);
    return orig;
}

fn disableRawMode(orig: posix.termios) void {
    posix.tcsetattr(STDIN_FD, .NOW, orig) catch {};
}

// write helper – single syscall
fn writeAll(fd: posix.fd_t, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n: usize = @intCast(c.write(fd, bytes[off..].ptr, bytes[off..].len));
        if (n == 0) break;
        if (@as(isize, @bitCast(n)) < 0) break;
        off += n;
    }
}

// ANSI helpers
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
    // terminal is 1-indexed
    try buf.print(alloc, "\x1b[{d};{d}H", .{ row + 1, col + 1 });
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------
const Input = struct {
    jump: bool = false,
    duck: bool = false,
    duck_hold: bool = false,
    quit: bool = false,
    restart: bool = false,
};

fn pollInput() Input {
    var inp = Input{};
    var fds = [_]posix.pollfd{.{ .fd = STDIN_FD, .events = posix.POLL.IN, .revents = 0 }};
    const n = posix.poll(&fds, 0) catch 0;
    if (n == 0) return inp;
    if (fds[0].revents & posix.POLL.IN == 0) return inp;

    var buf: [64]u8 = undefined;
    const read_n = posix.read(STDIN_FD, &buf) catch 0;
    if (read_n == 0) return inp;
    var i: usize = 0;
    while (i < read_n) : (i += 1) {
        const ch = buf[i];
        switch (ch) {
            3, // Ctrl-C
            27 => { // ESC – could be arrow
                // check if next bytes are '[' 'A' etc
                if (i + 2 < read_n and buf[i + 1] == '[') {
                    const arrow = buf[i + 2];
                    if (arrow == 'A') { // up
                        inp.jump = true;
                        i += 2;
                    } else if (arrow == 'B') { // down
                        inp.duck = true;
                        inp.duck_hold = true;
                        i += 2;
                    } else if (arrow == 'C') {
                        // right – ignore
                        i += 2;
                    } else if (arrow == 'D') {
                        i += 2;
                    }
                } else {
                    // lone ESC = quit
                    inp.quit = true;
                }
            },
            ' ', 'w', 'W', 'k', 'K' => inp.jump = true,
            '\r', '\n' => {
                inp.jump = true;
                inp.restart = true;
            },
            's', 'S', 'j', 'J' => {
                inp.duck = true;
                inp.duck_hold = true;
            },
            'q', 'Q' => inp.quit = true,
            'r', 'R' => inp.restart = true,
            else => {},
        }
        if (ch == 'q' or ch == 'Q') inp.quit = true;
    }
    // For duck hold detection: if any duck key seen, set hold.
    // Terminal autorepeat will keep sending 's' while held.
    return inp;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
fn render(game: *Game, buf: *std.ArrayList(u8)) !void {
    const alloc = game.allocator;
    buf.clearRetainingCapacity();
    // we render directly with ANSI cursor moves – no need to clear each cell
    // start frame
    try buf.appendSlice(alloc, "\x1b[H"); // home

    const w = game.width;
    const h = game.height;
    const gy = game.groundY();

    // colors – chrome uses #535353 grey, inverted is white on black
    const fg = if (game.inverted) "\x1b[97m" else "\x1b[90m";
    const cactus_fg = if (game.inverted) "\x1b[97m" else "\x1b[32m";
    const dino_fg = if (game.inverted) "\x1b[97;1m" else "\x1b[37;1m";
    const cloud_fg = "\x1b[37m";
    const dim = "\x1b[2m";
    const reset = "\x1b[0m";

    // if too small, show message centered
    if (w < 40 or h < 12) {
        try clearScreen(buf, alloc);
        try buf.appendSlice(alloc, fg);
        const msg = " TERMINAL TOO SMALL – enlarge to play ";
        const row = @divFloor(h, 2);
        const col = @max(0, @divFloor(w - @as(i32, @intCast(msg.len)), 2));
        try moveTo(buf, alloc, row, col);
        try buf.appendSlice(alloc, msg);
        try buf.appendSlice(alloc, reset);
        return;
    }

    // ---- background fill (optional inverted) ----
    if (game.inverted) {
        // fill with inverted background illusion – set reverse video
        try buf.appendSlice(alloc, "\x1b[40m\x1b[2J\x1b[H");
    } else {
        // normal – clear
        try buf.appendSlice(alloc, "\x1b[49m\x1b[2J\x1b[H");
    }

    // ---- score header (top right) ----
    // Chrome format: HI 00000  00000
    {
        var score_buf: [32]u8 = undefined;
        const score_str = try std.fmt.bufPrint(&score_buf, "{d:0>5}", .{game.score});
        var hi_buf: [32]u8 = undefined;
        const hi_str = try std.fmt.bufPrint(&hi_buf, "{d:0>5}", .{game.hi_score});
        const header = try std.fmt.allocPrint(alloc, "HI {s}  {s}", .{ hi_str, score_str });
        defer alloc.free(header);
        try buf.appendSlice(alloc, fg);
        try buf.appendSlice(alloc, dim);
        // right align
        const col = w - @as(i32, @intCast(header.len)) - 2;
        try moveTo(buf, alloc, 0, col);
        try buf.appendSlice(alloc, header);
        try buf.appendSlice(alloc, reset);
    }

    // ---- speed indicator (optional) ----
    // tiny speed bar under score? not needed

    // ---- clouds ----
    try buf.appendSlice(alloc, cloud_fg);
    for (game.clouds.items) |cl| {
        const cx: i32 = @intFromFloat(@round(cl.x));
        if (cx < -4 or cx >= w) continue;
        try moveTo(buf, alloc, cl.y, cx);
        // clip cloud to screen
        const cloud_str = CLOUD;
        const avail = w - cx;
        if (avail >= 3) {
            try buf.appendSlice(alloc, cloud_str);
        } else if (avail > 0) {
            try buf.appendSlice(alloc, cloud_str[0..@intCast(avail * 3)]); // rough – 3 bytes per cloud char
        }
    }
    try buf.appendSlice(alloc, reset);

    // ---- ground ----
    try buf.appendSlice(alloc, fg);
    // draw solid ground line
    try moveTo(buf, alloc, gy, 0);
    // build ground line with scroll texture: pattern "─▁──▁"
    var ground_line: [512]u8 = undefined;
    const glen: usize = @min(@as(usize, @intCast(w)), ground_line.len);
    var gi: usize = 0;
    const offset: usize = @intFromFloat(@mod(game.ground_scroll, 12));
    while (gi < glen) : (gi += 1) {
        const pattern_idx = (gi + offset) % 12;
        // simple dotted ground like chrome: ─ ─ · ·
        if (pattern_idx == 3 or pattern_idx == 7 or pattern_idx == 11) {
            // small bump – use 3-byte utf8 for ▁ (e2 96 81) – ascii fallback '.'
            if (gi + 2 < glen) {
                // we use ascii '.' to avoid multibyte messing alignment – but keep utf8 for style?
                // Use '_' for bump
                ground_line[gi] = '_';
            } else {
                ground_line[gi] = '-';
            }
        } else {
            ground_line[gi] = '-';
        }
    }
    // Ground uses '-' and '_' – single byte, simple
    try buf.appendSlice(alloc, ground_line[0..glen]);
    // ground bottom padding (chrome has solid line + second pixel?)
    if (gy + 1 < h) {
        try moveTo(buf, alloc, gy + 1, 0);
        var j: usize = 0;
        while (j < glen) : (j += 1) {
            ground_line[j] = ' ';
        }
        try buf.appendSlice(alloc, ground_line[0..glen]);
    }
    try buf.appendSlice(alloc, reset);

    // ---- obstacles ----
    for (game.obstacles.items) |o| {
        const ox: i32 = @intFromFloat(@round(o.x));
        if (ox + o.w < 0 or ox >= w) continue;
        const is_ptero = o.kind == .ptero_low or o.kind == .ptero_mid or o.kind == .ptero_high;
        // pick sprite
        var sprite: []const []const u8 = &.{};
        var sprite_h: i32 = o.h;
        if (is_ptero) {
            // animate flap every 10 frames
            const flap = (game.frame / 8) % 2 == 0;
            sprite = if (flap) &PTERO_A else &PTERO_B;
            sprite_h = 2;
        } else {
            switch (o.kind) {
                .cactus_small_single => {
                    sprite = &CACTUS_SMALL_SINGLE;
                    sprite_h = 3;
                },
                .cactus_small_double => {
                    sprite = &CACTUS_SMALL_DOUBLE;
                    sprite_h = 3;
                },
                .cactus_small_triple => {
                    sprite = &CACTUS_SMALL_TRIPLE;
                    sprite_h = 3;
                },
                .cactus_large_single => {
                    sprite = &CACTUS_LARGE_SINGLE;
                    sprite_h = 4;
                },
                .cactus_large_double => {
                    sprite = &CACTUS_LARGE_DOUBLE;
                    sprite_h = 4;
                },
                .cactus_large_triple => {
                    sprite = &CACTUS_LARGE_TRIPLE;
                    sprite_h = 4;
                },
                else => {
                    sprite = &CACTUS_SMALL_SINGLE;
                    sprite_h = 3;
                },
            }
        }
        try buf.appendSlice(alloc, cactus_fg);
        // obstacles y: ground-relative or ptero absolute
        const oy: i32 = if (is_ptero) o.y else gy - sprite_h + 1;
        var row: i32 = 0;
        while (row < sprite_h) : (row += 1) {
            const y = oy + row;
            if (y < 0 or y >= h) continue;
            const line = sprite[@intCast(row)];
            // clip horizontally
            if (ox < 0) {
                // compute byte offset – tricky with utf8, but cactus uses ascii/block? Our sprites are single-byte plus block (3 bytes)
                // For simplicity, skip offscreen left clipping by char count – approximate
                const skip: usize = @intCast(-ox);
                // Find byte offset for char skip – count chars (each char may be 1 or 3 bytes for block)
                // Our cactus sprites use ' ' (1), '█' (3 bytes), etc. Simpler: just not clip left, just draw if ox>=0.
                // To keep simple, just skip drawing when ox<0 and shift
                // We'll fallback to not drawing left-clipped – just start at col 0 with truncated string
                // Calculate char length?
                // Easier: use moveTo at 0 and slice string after skip – but byte length ≠ char length.
                // We'll just skip this obstacle when partially off left to avoid corruption – not perfect but fine
                if (ox != 0) continue;
                try moveTo(buf, alloc, y, 0);
                // attempt to slice by byte – may cut block char but okay
                const start = @min(skip * 3, line.len);
                if (start < line.len) {
                    const remain = line[start..];
                    const max_len = @min(remain.len, @as(usize, @intCast(w)));
                    try buf.appendSlice(alloc, remain[0..max_len]);
                }
            } else {
                const avail: i32 = w - ox;
                if (avail <= 0) continue;
                try moveTo(buf, alloc, y, ox);
                // clip to avail characters – approximate by byte length; just truncate byte-wise but keep within width
                // Estimate max bytes: avail * 3 (worst case block)
                const max_bytes: usize = @intCast(avail * 3);
                const to_write: usize = @min(line.len, max_bytes);
                // but we need to avoid cutting utf8 in middle – just write whole line if it fits, else trim at char boundary
                // Simpler: write line, terminal will clip.
                try buf.appendSlice(alloc, line[0..to_write]);
            }
        }
        try buf.appendSlice(alloc, reset);
    }

    // ---- dino ----
    {
        try buf.appendSlice(alloc, dino_fg);
        const is_dead = game.state == .game_over;
        var dino_sprite: []const []const u8 = undefined;
        var dh: i32 = DINO_HEIGHT;
        if (is_dead) {
            dino_sprite = &DINO_DEAD;
            dh = 4;
        } else if (!game.on_ground) {
            dino_sprite = &DINO_JUMP;
            dh = 4;
        } else if (game.ducking) {
            const flap = (game.frame / 6) % 2 == 0;
            dino_sprite = if (flap) &DINO_DUCK_A else &DINO_DUCK_B;
            dh = 3;
        } else if (game.state == .idle) {
            dino_sprite = &DINO_RUN_A;
            dh = 4;
        } else {
            const flap = (game.frame / 5) % 2 == 0;
            dino_sprite = if (flap) &DINO_RUN_A else &DINO_RUN_B;
            dh = 4;
        }
        const dy = game.dinoTopY();
        // dino may be clipped if jumping off screen top – handle
        var r: i32 = 0;
        while (r < dh) : (r += 1) {
            const y = dy + r;
            if (y < 0 or y >= h) continue;
            const line = dino_sprite[@intCast(r)];
            try moveTo(buf, alloc, y, DINO_X);
            try buf.appendSlice(alloc, line);
        }
        try buf.appendSlice(alloc, reset);
        // optional hitbox debug: uncomment to see
        // if (game.frame % 10 == 0) {}
    }

    // ---- UI overlays ----
    if (game.state == .idle) {
        const msg = if (game.blink) "  Press SPACE / ↑ to start  " else "                            ";
        const hint = "  ↓ to duck | Q to quit  ";
        const r1 = @divFloor(h, 2) + 2;
        const c1 = @max(0, @divFloor(w - @as(i32, @intCast(msg.len)), 2));
        const c2 = @max(0, @divFloor(w - @as(i32, @intCast(hint.len)), 2));
        try buf.appendSlice(alloc, "\x1b[97;1m");
        try moveTo(buf, alloc, r1, c1);
        try buf.appendSlice(alloc, msg);
        try buf.appendSlice(alloc, reset);
        try buf.appendSlice(alloc, dim);
        try moveTo(buf, alloc, r1 + 1, c2);
        try buf.appendSlice(alloc, hint);
        try buf.appendSlice(alloc, reset);

        // title
        const title = " CHROME DINO ";
        const title_col = @max(0, @divFloor(w - @as(i32, @intCast(title.len)), 2));
        try moveTo(buf, alloc, 2, title_col);
        try buf.appendSlice(alloc, "\x1b[1m");
        try buf.appendSlice(alloc, title);
        try buf.appendSlice(alloc, reset);
    } else if (game.state == .game_over) {
        const over = " G A M E  O V E R ";
        const over_col = @max(0, @divFloor(w - @as(i32, @intCast(over.len)), 2));
        const r = @divFloor(h, 2) - 2;
        try moveTo(buf, alloc, r, over_col);
        try buf.appendSlice(alloc, "\x1b[91;1m");
        try buf.appendSlice(alloc, over);
        try buf.appendSlice(alloc, reset);

        const score_msg = try std.fmt.allocPrint(alloc, " Score: {d}  HI: {d} ", .{ game.score, game.hi_score });
        defer alloc.free(score_msg);
        const sc_col = @max(0, @divFloor(w - @as(i32, @intCast(score_msg.len)), 2));
        try moveTo(buf, alloc, r + 1, sc_col);
        try buf.appendSlice(alloc, dim);
        try buf.appendSlice(alloc, score_msg);
        try buf.appendSlice(alloc, reset);

        const restart = if (game.blink) " Press SPACE or R to restart " else "                             ";
        const rc = @max(0, @divFloor(w - @as(i32, @intCast(restart.len)), 2));
        try moveTo(buf, alloc, r + 3, rc);
        try buf.appendSlice(alloc, "\x1b[97;1m");
        try buf.appendSlice(alloc, restart);
        try buf.appendSlice(alloc, reset);

        const quit_msg = " Q to quit ";
        const qc = @max(0, @divFloor(w - @as(i32, @intCast(quit_msg.len)), 2));
        try moveTo(buf, alloc, r + 4, qc);
        try buf.appendSlice(alloc, dim);
        try buf.appendSlice(alloc, quit_msg);
        try buf.appendSlice(alloc, reset);
    }

    // ---- footer with controls hint when playing (subtle) ----
    if (game.state == .playing) {
        const footer = "SPACE/↑ jump  ↓ duck  Q quit";
        const fc = @max(0, w - @as(i32, @intCast(footer.len)) - 1);
        try moveTo(buf, alloc, h - 1, fc);
        try buf.appendSlice(alloc, "\x1b[90;2m");
        // only show if width allows
        if (w > 40) try buf.appendSlice(alloc, footer);
        try buf.appendSlice(alloc, reset);
    }

    // ensure cursor at bottom
    try moveTo(buf, alloc, h - 1, 0);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Check if stdin is tty – if not, can't play (but allow build)
    const is_tty = c.isatty(STDIN_FD) != 0;
    if (!is_tty) {
        std.debug.print("Not a TTY. Please run in a terminal.\n", .{});
        return;
    }

    var ws = getWinsize();
    var game = Game.init(alloc, ws.cols, ws.rows);
    defer game.deinit();
    game.reset();

    // terminal setup
    const orig = enableRawMode() catch |e| {
        std.debug.print("failed to enable raw mode: {any}\n", .{e});
        return;
    };
    defer disableRawMode(orig);

    // alt screen + hide cursor
    var tmp_buf: std.ArrayList(u8) = .empty;
    defer tmp_buf.deinit(alloc);

    // build initial alt/hide sequence
    tmp_buf.clearRetainingCapacity();
    try enterAlt(&tmp_buf, alloc);
    try hideCursor(&tmp_buf, alloc);
    try bufAppend(&tmp_buf, alloc, "\x1b[2J\x1b[H");
    writeAll(STDOUT_FD, tmp_buf.items);

    defer {
        // restore on exit
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(alloc);
        out.appendSlice(alloc, "\x1b[0m") catch {};
        showCursor(&out, alloc) catch {};
        leaveAlt(&out, alloc) catch {};
        // also reset attributes
        writeAll(STDOUT_FD, out.items);
        disableRawMode(orig);
    }

    var frame_buf: std.ArrayList(u8) = .empty;
    defer frame_buf.deinit(alloc);

    var last_time: i128 = nowNs();
    var acc: i128 = 0;

    var running = true;
    while (running) {
        const now: i128 = nowNs();
        var delta: i128 = now - last_time;
        last_time = now;
        // clamp delta to avoid spiral if terminal lag
        if (delta > 100_000_000) delta = 100_000_000;
        if (delta < 0) delta = 0;
        acc += delta;

        // poll input each iteration
        var jump = false;
        var duck = false;
        var duck_hold = false;
        var should_quit = false;
        var should_restart = false;

        // we need to consume all pending input – pollInput already reads all buffered
        const inp = pollInput();
        jump = inp.jump;
        duck = inp.duck;
        duck_hold = inp.duck_hold;
        should_quit = inp.quit;
        should_restart = inp.restart;

        if (should_quit) {
            running = false;
            break;
        }

        // handle restart when game over
        if (game.state == .game_over and (jump or should_restart)) {
            // keep hi score
            const hi = game.hi_score;
            // full reset but hide old obstacles
            game.reset();
            game.hi_score = hi;
            // tiny delay to avoid immediate collision
            game.state = .playing;
            game.frame = 0;
            // play jump to start
        }

        // also handle 'r' restart mid-game? allow reset to idle?
        // not needed

        // check winsize occasionally (every 30 frames)
        if (game.frame % 30 == 0) {
            ws = getWinsize();
            game.width = ws.cols;
            game.height = ws.rows;
        }

        // fixed timestep update: consume acc
        // We want 1 game update per frame (60hz). So if acc >= FRAME_NS, update once.
        // To keep physics stable at 60, do while acc >= FRAME_NS { update; acc-=FRAME_NS }
        // But for smooth rendering, we update at least once per loop.
        var updated = false;
        while (acc >= FRAME_NS) : (acc -= FRAME_NS) {
            game.update(jump, duck, duck_hold);
            // after first update, clear jump/duck edge (jump is edge-triggered)
            jump = false;
            duck = false;
            // duck_hold stays? For hold we want continuous, so keep true if still holding
            // but we cleared – for simplicity after first, duck_hold remains as last
            // but we already consumed timer, so fine
            updated = true;
        }
        // if no fixed update yet (acc < FRAME_NS) still render at display rate?
        // We'll ensure at least one update if none happened and time passed small
        if (!updated and game.state == .playing) {
            // optional: interpolate? we just don't update
        }

        // render each loop (throttled to ~60fps via sleep)
        try render(&game, &frame_buf);
        writeAll(STDOUT_FD, frame_buf.items);

        // sleep to maintain target fps
        const after_render: i128 = nowNs();
        const elapsed = after_render - now;
        const target: i128 = @intCast(FRAME_NS);
        if (elapsed < target) {
            const sleep_ns: u64 = @intCast(target - elapsed);
            {
                var ts: c.timespec = .{ .sec = @intCast(sleep_ns / 1000000000), .nsec = @intCast(sleep_ns % 1000000000) };
                _ = c.nanosleep(&ts, null);
            }
        }

        // beep on game over? Use terminal bell once
        if (game.state == .game_over and game.frame % 60 == 1) {
            // ring bell
            writeAll(STDOUT_FD, "\x07");
        }
    }
}

fn bufAppend(buf: *std.ArrayList(u8), alloc: std.mem.Allocator, s: []const u8) !void {
    try buf.appendSlice(alloc, s);
}
