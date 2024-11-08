const std = @import("std");
const Allocator = std.mem.Allocator;
const mvzr = @import("mvzr.zig");
const Crc = std.hash.crc.Crc16DectX;

const ansi_escape = "\u{001b}";
const ansi_color_start = ansi_escape ++ "[38;5;{d}m";
const ansi_color_end = ansi_escape ++ "[0m";
const colorize_fmt_string = std.fmt.comptimePrint("{s}{{s}}{s}", .{ ansi_color_start, ansi_color_end });

fn colorize(allocator: Allocator, s: []const u8) ![]const u8 {
    const color = get_color(s);
    return std.fmt.allocPrint(allocator, colorize_fmt_string, .{ color, s });
}

fn colorize_line(allocator: Allocator, s: []const u8, match_it: *mvzr.Regex.RegexIterator) ![]const u8 {
    var start: usize = 0;
    var line = try std.ArrayList(u8).initCapacity(allocator, s.len);

    while (match_it.next()) |m| {
        // Color the current match
        const colorized_match = try colorize(allocator, m.slice);
        // Append everything from the end of the last match to the start of the current
        try line.appendSlice(s[start..m.start]);
        // Append the colorized match
        try line.appendSlice(colorized_match);
        allocator.free(colorized_match);
        // Update the cursor to the end of the match
        start = m.end;
    }

    // Append everything after the last match
    try line.appendSlice(s[start..]);
    return line.items;
}

fn get_color(s: []const u8) u8 {
    const hash = Crc.hash(s);
    // TODO: Lookup in a comptime colour table
    return @as(u8, @truncate(hash)) % 200 + 16;
}

pub fn main() !void {
    // TODO: Find an appropriate allocator
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    // Get pattern from command line
    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len != 2) {
        std.debug.print("Usage: zhl PATTERN\n", .{});
        std.process.exit(1);
    }

    const pattern = args[1];
    var br = std.io.bufferedReader(std.io.getStdIn().reader());
    var stdin = br.reader();

    const regex: mvzr.Regex = mvzr.compile(pattern) orelse {
        std.debug.print("Cannot parse regex pattern '{s}'\n", .{pattern});
        std.process.exit(1);
    };

    const buf = try allocator.alloc(u8, 4096);

    (read_loop: {
        while (stdin.readUntilDelimiterOrEof(buf, '\n') catch |e|
            break :read_loop e) |line|
        {
            var it = regex.iterator(line);
            const colorized_line = try colorize_line(allocator, line, &it);
            _ = try stdout.print("{s}\n", .{colorized_line});
            allocator.free(colorized_line);
        }
    }) catch |err| {
        std.debug.print("Got error: {any}\n", .{err});
        std.process.exit(1);
    };
}
