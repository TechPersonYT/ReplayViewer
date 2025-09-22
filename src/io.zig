const std = @import("std");
const rp = @import("replay.zig");
const mp = @import("map.zig");
const ms = @import("music.zig");
const rl = @import("raylib");

// By convention, download* functions take a URL and return parsed things
// Actual parsing and loading is handled in replay.zig, map.zig, and music.zig

pub fn webGet(url: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(allocator);
    defer response_writer.deinit();

    const response = try client.fetch(.{ .method = .GET, .location = .{ .url = url }, .response_writer = &response_writer.writer });

    if (response.status != .ok) {
        return error.HTTP;
    }

    return try response_writer.toOwnedSlice();
}

pub fn fetchReplayInfoFromID(id: u32, allocator: std.mem.Allocator) !struct { replay_url: []u8, map_url: []u8 } {
    std.debug.print("Fetching replay info from API\n", .{});

    const url = try std.fmt.allocPrint(allocator, "https://api.beatleader.xyz/score/{}", .{id});
    defer allocator.free(url);

    const data = try webGet(url, allocator);
    defer allocator.free(data);

    const json = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer json.deinit();

    const replay_url = json.value.object.get("replay").?.string;
    const owned_replay_url = try allocator.alloc(u8, replay_url.len);
    errdefer allocator.free(owned_replay_url);
    @memcpy(owned_replay_url, replay_url);

    const map_url = json.value.object.get("song").?.object.get("downloadUrl").?.string;
    const owned_map_url = try allocator.alloc(u8, map_url.len);
    errdefer allocator.free(owned_map_url);
    @memcpy(owned_map_url, map_url);

    return .{ .replay_url = owned_replay_url, .map_url = owned_map_url };
}

pub fn downloadReplay(url: []const u8, allocator: std.mem.Allocator) !rp.Replay {
    std.debug.print("Downloading replay\n", .{});

    const data = try webGet(url, allocator);

    var reader = std.Io.Reader.fixed(data);
    defer allocator.free(reader.buffer);

    std.debug.print("Parsing replay\n", .{});

    return rp.parseReplay(&reader, allocator);
}

pub fn downloadMapAndMusic(url: []const u8, target_filename: []const u8, target_path: []const u8, output_music_filename: []const u8, allocator: std.mem.Allocator) !struct { mp.Map, rl.Music } {
    std.debug.print("Downloading map\n", .{});

    const zipped = try webGet(url, allocator);
    defer allocator.free(zipped);

    try std.fs.cwd().deleteTree(target_path);
    try std.fs.cwd().writeFile(.{ .sub_path = target_filename, .data = zipped });
    try std.fs.cwd().makePath(target_path);

    std.debug.print("Unzipping map\n", .{});
    {
        var directory = try std.fs.cwd().openDir(target_path, .{ .iterate = true });
        defer directory.close();

        const song_file = try std.fs.cwd().openFile(target_filename, .{});
        defer song_file.close();

        const unzip_buffer = try allocator.alloc(u8, 100000000);
        defer allocator.free(unzip_buffer);

        var reader = song_file.reader(unzip_buffer);
        try std.zip.extract(directory, &reader, .{});
    }

    const map_data = .{ try mp.parseMapFile(target_path, allocator), try ms.convertAndLoadMusic(target_path, output_music_filename, allocator) };

    try std.fs.cwd().deleteTree(target_path);
    try std.fs.cwd().deleteFile(target_filename);

    return map_data;
}
