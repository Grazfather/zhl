const std = @import("std");
const Allocator = std.mem.Allocator;
const mvzr = @import("mvzr.zig");
const Crc = std.hash.crc.Crc16DectX;

const ansi_escape = "\x1b";
const ansi_color_start = ansi_escape ++ "[38;5;{}m";
const ansi_color_end = ansi_escape ++ "[0m";
const colorize_fmt_string = std.fmt.comptimePrint("{s}{{s}}{s}", .{ ansi_color_start, ansi_color_end });

fn colorize_line(allocator: Allocator, line: []const u8, regex: *const mvzr.Regex) ![]const u8 {
    var start: usize = 0;
    var output = try std.ArrayList(u8).initCapacity(allocator, line.len);

    var it = regex.iterator(line);
    while (it.next()) |match| {
        // Get the color for the current match
        const color = get_color(match.slice);
        // Append everything from the end of the last match to the start of the current
        try output.appendSlice(line[start..match.start]);
        // Append the colorized match
        try output.writer().print(ansi_color_start, .{color});
        try output.appendSlice(match.slice);
        try output.appendSlice(ansi_color_end);
        // Update the cursor to the end of the match
        start = match.end;
    }

    // Append everything after the last match
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

    // Get pattern from command line
    const args = try std.process.argsAlloc(allocator);
    // Not really needed with the arena deinit handles this
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: zhl PATTERN\n", .{});
        std.process.exit(1);
    }
    const pattern = args[1];

    const regex: mvzr.Regex = mvzr.compile(pattern) orelse {
        std.debug.print("Cannot parse regex pattern '{s}'\n", .{pattern});
        std.process.exit(1);
    };

    // Allocate enough to read a whole line
    var buf: [16 * 1024]u8 = undefined;

    while (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        const colorized_line = try colorize_line(allocator, line, &regex);
        _ = try stdout.print("{s}\n", .{colorized_line});
        // allocator.free(colorized_line);
        _ = arena.reset(.{ .retain_with_limit = 1 });
    }
}
