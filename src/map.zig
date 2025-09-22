const std = @import("std");

pub const Map = struct {};

pub fn parseMapFile(filename: []const u8, allocator: std.mem.Allocator) !Map {
    std.debug.print("Loading map\n", .{});

    const file = try std.fs.cwd().openFile(filename, .{});

    const buffer = try allocator.alloc(u8, try file.getEndPos() + 1);
    defer allocator.free(buffer);

    var reader = file.reader(buffer).interface;

    return parseMap(&reader, allocator);
}

pub fn parseMap(reader: *std.Io.Reader, allocator: std.mem.Allocator) !Map {
    // TODO
    _ = reader;
    _ = allocator;

    return .{};
}
