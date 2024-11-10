const std = @import("std");
const Allocator = std.mem.Allocator;
const mvzr = @import("mvzr");
const Crc = std.hash.crc.Crc16DectX;
const clap = @import("clap");

const ansi_escape = "\x1b";
const ansi_color_start = ansi_escape ++ "[38;5;{}m";
const ansi_color_end = ansi_escape ++ "[0m";
const colorize_fmt_string = std.fmt.comptimePrint("{s}{{s}}{s}", .{ ansi_color_start, ansi_color_end });

fn colorize_line(
    allocator: Allocator,
    line: []const u8,
    regex: *const mvzr.Regex,
    grep: bool,
    matches_only: bool,
) !?[]const u8 {
    var start: usize = 0;
    var output = try std.ArrayList(u8).initCapacity(allocator, line.len);

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

    // If we are grepping, but this line doesn't have a match, then we are done
    if (!matched and grep) {
        allocator.free(output.items);
        return undefined;
    }

    // Append everything after the last match
    if (!matches_only)
        try output.appendSlice(line[start..]);
    return output.items;
}

fn get_color(s: []const u8) u8 {
    const hash = std.hash.crc.Crc16DectX.hash(s);
    return @as(u8, @truncate(hash)) % 200 + 16;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    var br = std.io.bufferedReader(std.io.getStdIn().reader());
    var stdin = br.reader();

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
        try diag.report(std.io.getStdErr().writer(), err);
        try clap.usage(std.io.getStdErr().writer(), clap.Help, &params);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.usage(std.io.getStdErr().writer(), clap.Help, &params);
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
        return clap.usage(std.io.getStdErr().writer(), clap.Help, &params);
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

    // Allocate enough to read a whole line
    var buf: [16 * 1024]u8 = undefined;

    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const colorized_line = try colorize_line(allocator, line, &regex, grep, matches_only);
        if (colorized_line) |cl| {
            _ = try stdout.print("{s}\n", .{cl});
        }
        _ = arena.reset(.{ .retain_with_limit = 1 });
    }
}
