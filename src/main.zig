const std = @import("std");
const Crc = std.hash.crc.Crc16DectX;

const mvzr = @import("mvzr");
const clap = @import("clap");

const ansi_escape = "\x1b";
const ansi_color_start = ansi_escape ++ "[38;5;";
const ansi_color_end = ansi_escape ++ "[0m";

fn colorize_line(
    output: *std.array_list.Managed(u8),
    line: []const u8,
    regex: *const mvzr.Regex,
    grep: bool,
    matches_only: bool,
) !bool {
    output.clearRetainingCapacity();
    var start: usize = 0;

    var matched = false;
    var it = regex.iterator(line);
    while (it.next()) |match| {
        matched = true;
        // Get the color for the current match
        const color = get_color(match.slice);
        // Append everything from the end of the last match to the start of the current
        if (!matches_only)
            try output.appendSlice(line[start..match.start]);
        // Append the colorized match
        try output.appendSlice(ansi_color_start);
        var buf: [3]u8 = undefined; // u8 max is 255, so max 3 digits
        const len = std.fmt.printInt(&buf, color, 10, .lower, .{});
        try output.appendSlice(buf[0..len]);
        try output.appendSlice("m");
        try output.appendSlice(match.slice);
        try output.appendSlice(ansi_color_end);
        // Update the cursor to the end of the match
        start = match.end;
    }

    // If we are grepping, but this line doesn't have a match, then we are done, and we signal that
    // the output is invalid
    if (!matched and grep) {
        return false;
    }

    // Append everything after the last match
    if (!matches_only)
        try output.appendSlice(line[start..]);
    return true;
}

fn get_color(s: []const u8) u8 {
    const hash = std.hash.crc.Crc16DectX.hash(s);
    return @as(u8, @truncate(hash)) % 200 + 16;
}

fn process(
    allocator: std.mem.Allocator,
    reader: *std.io.Reader,
    writer: *std.io.Writer,
    regex: mvzr.Regex,
    grep: bool,
    matches_only: bool,
) !void {
    // Reusable buffer for colorizing lines
    var colorize_buffer = std.array_list.Managed(u8).init(allocator);
    defer colorize_buffer.deinit();

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

        if (try colorize_line(&colorize_buffer, line, &regex, grep, matches_only)) {
            _ = try writer.write(colorize_buffer.items);
        }
    }

    // Flush any remaining content
    try writer.flush();
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stderr_writer = std.fs.File.stderr().writer(&.{});
    var buffer: [1048576]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    var inbuf: [1048576]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&inbuf);

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

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
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

    try process(allocator, &stdin_reader.interface, &stdout_writer.interface, regex, grep, matches_only);
}

test "test input/output" {
    var out_buffer: [2 * 1024]u8 = undefined;
    var out_stream = std.io.Writer.fixed(&out_buffer);

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
        var in_stream = std.io.Reader.fixed(tc.input);
        out_stream = .fixed(&out_buffer);
        const regex = mvzr.compile(tc.regex).?;
        try process(std.testing.allocator, &in_stream, &out_stream, regex, false, false);
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
        expect_back: bool,
    }{
        // No match, but no grep or matches only, returns original line
        .{ .input = "Hello\n", .regex = "xxx", .grep = false, .mo = false, .expect_back = true },
        // Match, with grep, returns colorized line
        .{ .input = "Hello\n", .regex = "l", .grep = true, .mo = false, .expect_back = true },
        // Match, with match only, returns colorized match
        .{ .input = "Hello\n", .regex = "l", .grep = false, .mo = true, .expect_back = true },
        // No match, with grep, returns nothing
        .{ .input = "Hello\n", .regex = "xxx", .grep = true, .mo = false, .expect_back = false },
        // No match, with matches only, returns original line
        .{ .input = "Hello\n", .regex = "xxx", .grep = false, .mo = true, .expect_back = true },
    };

    var output = std.array_list.Managed(u8).init(std.testing.allocator);
    defer output.deinit();

    for (tcs) |tc| {
        const regex = mvzr.compile(tc.regex).?;
        const has_output = try colorize_line(&output, tc.input, &regex, tc.grep, tc.mo);
        if (has_output != tc.expect_back) {
            std.debug.print("Expected {}, got {}\n", .{ tc.expect_back, has_output });
            try std.testing.expect(false);
        }
    }
}
