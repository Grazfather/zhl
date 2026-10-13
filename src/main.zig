const std = @import("std");

const mvzr = @import("mvzr");
const clap = @import("clap");

const ansi_escape = "\x1b";
const ansi_color_end = ansi_escape ++ "[0m";

/// Comptime-generated lookup table of 200 precomputed ANSI color escape sequences.
/// Index 0 = color 16 ("\x1b[38;5;16m"), index 199 = color 215 ("\x1b[38;5;215m").
const color_table: [200][]const u8 = blk: {
    @setEvalBranchQuota(200 * 1000);
    var table: [200][]const u8 = undefined;
    for (0..200) |i| {
        table[i] = std.fmt.comptimePrint("\x1b[38;5;{d}m", .{i + 16});
    }
    break :blk table;
};

fn append(buf: []u8, pos: usize, data: []const u8) usize {
    const end = pos + data.len;
    @memcpy(buf[pos..end], data);
    return end;
}

fn colorize_line(
    buf: []u8,
    line: []const u8,
    regex: *const mvzr.Regex,
    grep: bool,
    matches_only: bool,
) usize {
    var start: usize = 0;
    var pos: usize = 0;
    var matched = false;

    var it = regex.iterator(line);
    while (it.next()) |match| {
        matched = true;
        if (!matches_only)
            pos = append(buf, pos, line[start..match.start]);
        const color_index = get_color(match.slice);
        pos = append(buf, pos, color_table[color_index]);
        pos = append(buf, pos, match.slice);
        pos = append(buf, pos, ansi_color_end);
        start = match.end;
    }

    if (!matched and grep) return 0;

    if (!matches_only)
        pos = append(buf, pos, line[start..]);

    return pos;
}

fn get_color(s: []const u8) u8 {
    const hash = std.hash.crc.Crc16DectX.hash(s);
    return @as(u8, @truncate(hash)) % 200;
}

fn process(
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    regex: mvzr.Regex,
    grep: bool,
    matches_only: bool,
) !void {
    // Stack buffer for colorized output — generous size for long lines with many matches
    var colorize_buf: [256 * 1024]u8 = undefined;

    var eof: bool = false;
    while (!eof) {
        const line = reader.takeDelimiterInclusive('\n') catch |err| blk: switch (err) {
            error.EndOfStream => {
                eof = true;
                break :blk reader.buffered();
            },
            else => |e| return e,
        };

        // If the input actually ends with a newline, then this will be an empty slice, so we break
        if (line.len == 0) break;

        const len = colorize_line(&colorize_buf, line, &regex, grep, matches_only);
        if (len > 0) {
            try writer.writeAll(colorize_buf[0..len]);
        }
    }

    // Flush any remaining content
    try writer.flush();
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stderr_writer: std.Io.File.Writer = .init(.stderr(), io, &.{});
    var buffer: [1048576]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    var inbuf: [1048576]u8 = undefined;
    var stdin_reader: std.Io.File.Reader = .init(.stdin(), io, &inbuf);

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-p, --pattern <str>    Regex pattern to highlight
        \\-d, --decimalnumbers   Highlight decimal digits
        \\-w, --words            Highlight (regex) words
        \\-x, --hexnumbers       Highlight hex numbers
        \\-g, --grep             Only print matching lines
        \\-m, --matchesonly      Only print matches
        \\
    );

    const gpa = init.gpa;
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.report(&stderr_writer.interface, err);
        try clap.usage(&stderr_writer.interface, clap.Help, &params);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.usage(&stderr_writer.interface, clap.Help, &params);
    }

    var grep = false;
    var matches_only = false;
    var pattern: []const u8 = undefined;
    if (res.args.pattern) |p| {
        pattern = p;
    } else if (res.args.decimalnumbers != 0) {
        pattern = "\\b\\d+\\b";
    } else if (res.args.words != 0) {
        pattern = "\\w+";
    } else if (res.args.hexnumbers != 0) {
        // mvzr doesn't support non capture groups, so we or two patterns
        // pattern = "\\b(?:0x)?[a-fA-F\\d]{2,}\\b";
        pattern = "0x[a-fA-F0-9]{2,}|[a-fA-F0-9]{2,}";
    } else {
        return clap.usage(&stderr_writer.interface, clap.Help, &params);
    }

    if (res.args.grep == 1) {
        grep = true;
    } else if (res.args.matchesonly == 1) {
        matches_only = true;
        grep = true;
    }

    const regex: mvzr.Regex = mvzr.compile(pattern) orelse {
        std.debug.print("Cannot parse regex pattern '{s}'\n", .{pattern});
        std.process.exit(1);
    };

    try process(&stdin_reader.interface, &stdout_writer.interface, regex, grep, matches_only);
}

test "test input/output" {
    var out_buffer: [2 * 1024]u8 = undefined;
    var out_stream = std.Io.Writer.fixed(&out_buffer);

    const tcs = [_]struct {
        input: []const u8,
        regex: []const u8,
        match_count: usize,
    }{
        .{ .input = "Hello\n", .regex = "xxx", .match_count = 0 },
        .{ .input = "Hello\n", .regex = "ell", .match_count = 1 },
        .{ .input = "Hello\n", .regex = "l", .match_count = 2 },
        .{ .input = "Hello\n", .regex = "[e|o]", .match_count = 2 },
    };

    for (tcs) |tc| {
        var in_stream = std.Io.Reader.fixed(tc.input);
        out_stream = .fixed(&out_buffer);
        const regex = mvzr.compile(tc.regex).?;
        try process(&in_stream, &out_stream, regex, false, false);
        try std.testing.expectEqual(std.mem.count(u8, out_stream.buffer, ansi_escape), tc.match_count * 2);
        try std.testing.expectEqual(std.mem.count(u8, out_stream.buffer, ansi_color_end), tc.match_count);
    }
}

test "test colorize functionality" {
    const tcs = [_]struct {
        input: []const u8,
        regex: []const u8,
        grep: bool,
        mo: bool,
        expect_output: bool,
    }{
        // No match, but no grep or matches only, returns original line
        .{ .input = "Hello\n", .regex = "xxx", .grep = false, .mo = false, .expect_output = true },
        // Match, with grep, returns colorized line
        .{ .input = "Hello\n", .regex = "l", .grep = true, .mo = false, .expect_output = true },
        // Match, with match only, returns colorized match
        .{ .input = "Hello\n", .regex = "l", .grep = false, .mo = true, .expect_output = true },
        // No match, with grep, returns nothing
        .{ .input = "Hello\n", .regex = "xxx", .grep = true, .mo = false, .expect_output = false },
        // No match, with matches only (implies grep), returns nothing
        .{ .input = "Hello\n", .regex = "xxx", .grep = true, .mo = true, .expect_output = false },
    };

    for (tcs) |tc| {
        var out_buffer: [2 * 1024]u8 = undefined;
        var out_stream = std.Io.Writer.fixed(&out_buffer);
        var in_stream = std.Io.Reader.fixed(tc.input);
        const regex = mvzr.compile(tc.regex).?;
        try process(&in_stream, &out_stream, regex, tc.grep, tc.mo);
        const has_output = out_stream.end > 0;
        if (has_output != tc.expect_output) {
            std.debug.print("Expected output={}, got output={}\n", .{ tc.expect_output, has_output });
            try std.testing.expect(false);
        }
    }
}
