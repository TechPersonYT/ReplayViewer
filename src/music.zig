const std = @import("std");
const rl = @import("raylib");

fn convertMapMusic(extracted_path: []const u8, output_filename: []const u8, allocator: std.mem.Allocator) !void {
    std.debug.print("Converting music\n", .{});

    const ffmpeg_command = try std.fmt.allocPrint(allocator, "ffmpeg -y -i {s}/*.egg {s}", .{ extracted_path, output_filename });
    defer allocator.free(ffmpeg_command);

    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = &.{ "bash", "-c", ffmpeg_command } });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    std.debug.print("Song conversion output: '{s}\n{s}'\n", .{ result.stdout, result.stderr });
}

pub fn convertAndLoadMusic(extracted_path: []const u8, music_filename: []const u8, allocator: std.mem.Allocator) !rl.Music {
    try convertMapMusic(extracted_path, music_filename, allocator);

    std.debug.print("Loading music\n", .{});

    var buffer: [2048]u8 = undefined;
    const terminated_filename = try std.fmt.bufPrintZ(&buffer, "{s}", .{music_filename});

    return rl.loadMusicStream(terminated_filename);
}
