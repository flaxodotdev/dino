//! Per-run history: one tab-separated line per game, appended to a file under
//! the XDG data dir, plus the report behind `dino view`.
//!
//! Everything here is best effort. A game that cannot write its history still
//! has to be a game, so failures are swallowed rather than surfaced.

const std = @import("std");
const c = std.c;

pub const VERSION = 1;

const HEADER = "# dino history v1\tstarted_unix\tduration_ms\tscore\tobstacles\tjumps\tducks\tspeed_x100\tending\n";

pub const Run = struct {
    started: i64 = 0,
    ms: i64 = 0,
    score: u32 = 0,
    obstacles: u32 = 0,
    jumps: u32 = 0,
    ducks: u32 = 0,
    /// top speed reached, in chrome's px/frame * 100, so runs on terminals of
    /// different widths stay comparable
    speed_x100: u32 = 0,
    death: bool = true,
};

// libc time, for local timestamps
const Tm = extern struct {
    sec: c_int,
    min: c_int,
    hour: c_int,
    mday: c_int,
    mon: c_int,
    year: c_int,
    wday: c_int,
    yday: c_int,
    isdst: c_int,
    gmtoff: c_long,
    zone: ?[*:0]const u8,
};
extern fn localtime_r(timep: *const i64, result: *Tm) ?*Tm;

const MONTHS = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

// ---------------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------------

/// $DINO_HISTORY, else $XDG_DATA_HOME/dino/history.tsv, else
/// $HOME/.local/share/dino/history.tsv.
pub fn filePath(buf: []u8) ?[:0]const u8 {
    if (c.getenv("DINO_HISTORY")) |p| {
        return std.fmt.bufPrintZ(buf, "{s}", .{std.mem.span(p)}) catch null;
    }
    if (c.getenv("XDG_DATA_HOME")) |x| {
        const dir = std.mem.span(x);
        if (dir.len != 0) {
            return std.fmt.bufPrintZ(buf, "{s}/dino/history.tsv", .{dir}) catch null;
        }
    }
    if (c.getenv("HOME")) |h| {
        return std.fmt.bufPrintZ(buf, "{s}/.local/share/dino/history.tsv", .{std.mem.span(h)}) catch null;
    }
    return null;
}

/// mkdir -p on everything up to the last separator.
fn ensureParent(path: [:0]const u8) void {
    var buf: [1024]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;

    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (buf[i] != '/') continue;
        buf[i] = 0;
        _ = c.mkdir(@ptrCast(&buf), 0o755); // EEXIST is the normal case
        buf[i] = '/';
    }
}

fn exists(path: [:0]const u8) bool {
    const f = c.fopen(path.ptr, "r") orelse return false;
    _ = c.fclose(f);
    return true;
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

pub fn append(run: Run) void {
    var pbuf: [1024]u8 = undefined;
    const path = filePath(&pbuf) orelse return;
    ensureParent(path);

    const had_file = exists(path);
    const f = c.fopen(path.ptr, "a") orelse return;
    defer _ = c.fclose(f);

    if (!had_file) _ = c.fwrite(HEADER.ptr, 1, HEADER.len, f);

    var line: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&line, "{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{s}\n", .{
        VERSION,
        run.started,
        run.ms,
        run.score,
        run.obstacles,
        run.jumps,
        run.ducks,
        run.speed_x100,
        if (run.death) "death" else "quit",
    }) catch return;
    _ = c.fwrite(text.ptr, 1, text.len, f);
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

pub fn load(alloc: std.mem.Allocator) ![]Run {
    var pbuf: [1024]u8 = undefined;
    const path = filePath(&pbuf) orelse return &.{};
    const f = c.fopen(path.ptr, "r") orelse return &.{};
    defer _ = c.fclose(f);

    var raw: std.ArrayList(u8) = .empty;
    defer raw.deinit(alloc);
    var chunk: [8192]u8 = undefined;
    while (true) {
        const n = c.fread(&chunk, 1, chunk.len, f);
        if (n == 0) break;
        try raw.appendSlice(alloc, chunk[0..n]);
    }

    var runs: std.ArrayList(Run) = .empty;
    errdefer runs.deinit(alloc);

    var lines = std.mem.splitScalar(u8, raw.items, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (parseLine(trimmed)) |run| try runs.append(alloc, run);
    }
    return runs.toOwnedSlice(alloc);
}

fn parseLine(line: []const u8) ?Run {
    var it = std.mem.splitScalar(u8, line, '\t');
    var fields: [9][]const u8 = undefined;
    var n: usize = 0;
    while (it.next()) |f| : (n += 1) {
        if (n == fields.len) break;
        fields[n] = f;
    }
    if (n < 9) return null;
    if (num(u32, fields[0]) != VERSION) return null;

    return .{
        .started = num(i64, fields[1]) orelse return null,
        .ms = num(i64, fields[2]) orelse return null,
        .score = num(u32, fields[3]) orelse return null,
        .obstacles = num(u32, fields[4]) orelse 0,
        .jumps = num(u32, fields[5]) orelse 0,
        .ducks = num(u32, fields[6]) orelse 0,
        .speed_x100 = num(u32, fields[7]) orelse 0,
        .death = std.mem.eql(u8, fields[8], "death"),
    };
}

fn num(comptime T: type, s: []const u8) ?T {
    return std.fmt.parseInt(T, s, 10) catch null;
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

fn fmtWhen(buf: []u8, unix: i64) []const u8 {
    var t: i64 = unix;
    var tm: Tm = undefined;
    if (localtime_r(&t, &tm) == null) return "?";
    const mon: usize = @intCast(@mod(tm.mon, 12));
    // cast away the sign, otherwise zero padding prints a leading '+'
    return std.fmt.bufPrint(buf, "{d} {s} {d:0>2}:{d:0>2}", .{
        @as(u32, @intCast(@max(0, tm.mday))),
        MONTHS[mon],
        @as(u32, @intCast(@max(0, tm.hour))),
        @as(u32, @intCast(@max(0, tm.min))),
    }) catch "?";
}

fn fmtDur(buf: []u8, ms: i64) []const u8 {
    const total_s = @divTrunc(ms, 1000);
    const m = @divTrunc(total_s, 60);
    const sec = @mod(total_s, 60);
    if (m >= 60) {
        return std.fmt.bufPrint(buf, "{d}h{d:0>2}m", .{ @divTrunc(m, 60), @mod(m, 60) }) catch "?";
    }
    if (m > 0) return std.fmt.bufPrint(buf, "{d}m{d:0>2}s", .{ m, sec }) catch "?";
    return std.fmt.bufPrint(buf, "{d}s", .{sec}) catch "?";
}

const BAR_W: usize = 28;

/// Build the `dino view` report. Caller owns the returned bytes.
pub fn report(alloc: std.mem.Allocator, runs: []const Run) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);

    if (runs.len == 0) {
        var pbuf: [1024]u8 = undefined;
        const path = filePath(&pbuf) orelse "(nowhere to write)";
        try out.print(alloc, "no runs recorded yet\n\nplay a game and they land in {s}\n", .{path});
        return out.toOwnedSlice(alloc);
    }

    var total_ms: i64 = 0;
    var total_score: u64 = 0;
    var total_obstacles: u64 = 0;
    var deaths: u32 = 0;
    var best = runs[0];
    var longest = runs[0];
    var most_obs = runs[0];
    var top_speed: u32 = 0;

    for (runs) |r| {
        total_ms += r.ms;
        total_score += r.score;
        total_obstacles += r.obstacles;
        if (r.death) deaths += 1;
        if (r.score > best.score) best = r;
        if (r.ms > longest.ms) longest = r;
        if (r.obstacles > most_obs.obstacles) most_obs = r;
        if (r.speed_x100 > top_speed) top_speed = r.speed_x100;
    }

    var b1: [64]u8 = undefined;
    var b2: [64]u8 = undefined;

    try out.print(alloc, "\ndino  -  {d} runs, {s} played\n\n", .{ runs.len, fmtDur(&b1, total_ms) });

    try out.print(alloc, "  best score       {d:0>5}    {s}\n", .{ best.score, fmtWhen(&b1, best.started) });
    try out.print(alloc, "  longest run      {s: <8} {s}\n", .{ fmtDur(&b2, longest.ms), fmtWhen(&b1, longest.started) });
    try out.print(alloc, "  most obstacles   {d: <8} {s}\n", .{ most_obs.obstacles, fmtWhen(&b1, most_obs.started) });
    try out.print(alloc, "  average score    {d}\n", .{total_score / runs.len});
    try out.print(alloc, "  average run      {s}\n", .{fmtDur(&b1, @divTrunc(total_ms, @as(i64, @intCast(runs.len))))});
    try out.print(alloc, "  obstacles seen   {d}\n", .{total_obstacles});
    try out.print(alloc, "  top speed        {d}.{d:0>2} px/frame\n", .{ top_speed / 100, top_speed % 100 });
    try out.print(alloc, "  ended            {d} deaths, {d} quits\n\n", .{ deaths, runs.len - deaths });

    // last runs, newest first
    const show = @min(runs.len, 12);
    try out.print(alloc, "  last {d} runs\n", .{show});
    var i: usize = runs.len;
    var max_shown: u32 = 1;
    while (i > runs.len - show) {
        i -= 1;
        if (runs[i].score > max_shown) max_shown = runs[i].score;
    }
    i = runs.len;
    while (i > runs.len - show) {
        i -= 1;
        const r = runs[i];
        const filled: usize = @intFromFloat(@round(@as(f32, @floatFromInt(r.score)) /
            @as(f32, @floatFromInt(max_shown)) * @as(f32, @floatFromInt(BAR_W))));
        try out.print(alloc, "    {s: <13} {d:0>5}  {s: <7} {d: >3} obs  ", .{
            fmtWhen(&b1, r.started), r.score, fmtDur(&b2, r.ms), r.obstacles,
        });
        var k: usize = 0;
        while (k < BAR_W) : (k += 1) {
            try out.appendSlice(alloc, if (k < filled) "\u{2588}" else " ");
        }
        try out.print(alloc, "  {s}\n", .{if (r.death) "death" else "quit"});
    }
    try out.appendSlice(alloc, "\n");

    return out.toOwnedSlice(alloc);
}
