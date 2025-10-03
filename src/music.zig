const std = @import("std");
const log = std.log.scoped(.music);
const rl = @import("raylib");

fn convert(extracted_path: []const u8, output_filename: []const u8, allocator: std.mem.Allocator) !void {
    log.debug("Converting file", .{});

    const ffmpeg_command = try std.fmt.allocPrint(allocator, "ffmpeg -y -i {s}/*.egg {s}", .{ extracted_path, output_filename });
    defer allocator.free(ffmpeg_command);

    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = &.{ "bash", "-c", ffmpeg_command } });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    log.debug("Song conversion output: '{s}\n{s}'", .{ result.stdout, result.stderr });
}

pub fn convertAndLoad(extracted_path: []const u8, music_filename: []const u8, allocator: std.mem.Allocator) !rl.Music {
    try convert(extracted_path, music_filename, allocator);

    log.debug("Loading file", .{});

    var buffer: [2048]u8 = undefined;
    const terminated_filename = try std.fmt.bufPrintZ(&buffer, "{s}", .{music_filename});

    log.debug("Got filename '{s}'", .{terminated_filename});

    return rl.loadMusicStream(terminated_filename);
}
