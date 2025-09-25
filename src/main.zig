const std = @import("std");
const Crc = std.hash.crc.Crc16DectX;

const mvzr = @import("mvzr");
const clap = @import("clap");

const ansi_escape = "\x1b";
const ansi_color_start = ansi_escape ++ "[38;5;{}m";
const ansi_color_end = ansi_escape ++ "[0m";

const OUTPUT_BUFFER_SIZE = 4 * 1024;

const BufferedOutput = struct {
    buffer: []u8,
    pos: usize = 0,
    writer: std.io.AnyWriter,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter) !BufferedOutput {
        return .{
            .buffer = try allocator.alloc(u8, OUTPUT_BUFFER_SIZE),
            .writer = writer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BufferedOutput) void {
        self.allocator.free(self.buffer);
    }

    pub fn append(self: *BufferedOutput, content: []const u8) !void {
        const remaining = self.buffer.len - self.pos;
        if (content.len + 1 > remaining) {
            try self.flush();
        }

        @memcpy(self.buffer[self.pos .. self.pos + content.len], content);
        self.pos += content.len;
        self.buffer[self.pos] = '\n';
        self.pos += 1;
    }

    pub fn flush(self: *BufferedOutput) !void {
        if (self.pos > 0) {
            try self.writer.writeAll(self.buffer[0..self.pos]);
            self.pos = 0;
        }
    }
};

fn colorize_line(
    output: *std.ArrayList(u8),
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
        try output.writer().print(ansi_color_start, .{color});
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
    reader: std.io.AnyReader,
    writer: std.io.AnyWriter,
    regex: mvzr.Regex,
    grep: bool,
    matches_only: bool,
) !void {
    var buffered_output = try BufferedOutput.init(allocator, writer);
    defer buffered_output.deinit();

    // Reusable buffer for colorizing lines
    var colorize_buffer = std.ArrayList(u8).init(allocator);
    defer colorize_buffer.deinit();

    // Allocate enough to read a whole line
    var buf: [16 * 1024]u8 = undefined;

    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (try colorize_line(&colorize_buffer, line, &regex, grep, matches_only)) {
            try buffered_output.append(colorize_buffer.items);
        }
    }

    // Flush any remaining content
    try buffered_output.flush();
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stderr = std.io.getStdErr().writer().any();
    const stdout = std.io.getStdOut().writer().any();
    var br = std.io.bufferedReader(std.io.getStdIn().reader());
    const stdin = br.reader().any();

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
        try diag.report(stderr, err);
        try clap.usage(stderr, clap.Help, &params);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.usage(stderr, clap.Help, &params);
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
        return clap.usage(stderr, clap.Help, &params);
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

    try process(allocator, stdin, stdout, regex, grep, matches_only);
}

test "test input/output" {
    var in_buffer: [1024]u8 = undefined;
    var in_stream = std.io.fixedBufferStream(&in_buffer);
    var out_buffer: [2 * 1024]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&out_buffer);

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
        try in_stream.seekTo(0);
        try in_stream.writer().writeAll(tc.input);
        try in_stream.seekTo(0);
        try out_stream.seekTo(0);
        const regex = mvzr.compile(tc.regex).?;
        try process(std.testing.allocator, in_stream.reader().any(), out_stream.writer().any(), regex, false, false);
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

    var output = std.ArrayList(u8).init(std.testing.allocator);
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
