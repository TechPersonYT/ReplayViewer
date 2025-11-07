const std = @import("std");
const log = std.log.scoped(.io);
const rp = @import("replay.zig");
const mp = @import("map.zig");
const ms = @import("music.zig");
const rl = @import("raylib");

// By convention, download* functions take a URL and return parsed things
// Actual parsing and loading is handled in replay.zig, map.zig, and music.zig

pub fn webGet(url: []const u8, allocator: std.mem.Allocator) ![]u8 {
    log.debug("GET '{s}'", .{url});

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(allocator);
    defer response_writer.deinit();

    const response = try client.fetch(.{ .method = .GET, .location = .{ .url = url }, .response_writer = &response_writer.writer });

    if (response.status != .ok) {
        log.err("Received status {}", .{response.status});

        return error.HTTP;
    }

    return try response_writer.toOwnedSlice();
}

pub fn fetchReplayInfoFromID(id: u32, allocator: std.mem.Allocator) !struct { replay_url: []u8, map_url: []u8, map_filename: []u8 } {
    log.debug("Fetching replay info from API", .{});

    const url = try std.fmt.allocPrint(allocator, "https://api.beatleader.xyz/score/{}", .{id});
    defer allocator.free(url);

    const data = try webGet(url, allocator);
    defer allocator.free(data);

    const json = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer json.deinit();

    const replay_url = json.value.object.get("replay").?.string;
    log.debug("Replay URL: '{s}'", .{replay_url});
    const owned_replay_url = try allocator.alloc(u8, replay_url.len);
    errdefer allocator.free(owned_replay_url);
    @memcpy(owned_replay_url, replay_url);

    const map_url = json.value.object.get("song").?.object.get("downloadUrl").?.string;
    log.debug("Map URL: '{s}'", .{map_url});
    const owned_map_url = try allocator.alloc(u8, map_url.len);
    errdefer allocator.free(owned_map_url);
    @memcpy(owned_map_url, map_url);

    const difficulty_name = json.value.object.get("difficulty").?.object.get("difficultyName").?.string;
    const mode_name = json.value.object.get("difficulty").?.object.get("modeName").?.string;
    const map_filename = try std.fmt.allocPrint(allocator, "{s}{s}.dat", .{ difficulty_name, mode_name });
    log.debug("Map filename: '{s}'", .{map_filename});

    return .{ .replay_url = owned_replay_url, .map_url = owned_map_url, .map_filename = map_filename };
}

pub fn downloadReplay(url: []const u8, allocator: std.mem.Allocator) !rp.Replay {
    log.debug("Downloading replay", .{});

    const data = try webGet(url, allocator);

    var reader = std.Io.Reader.fixed(data);
    defer allocator.free(reader.buffer);

    log.debug("Parsing replay", .{});

    return rp.parse(&reader, allocator);
}

pub fn downloadMapAndMusic(url: []const u8, target_filename: []const u8, target_path: []const u8, map_filename: []const u8, output_music_filename: []const u8, allocator: std.mem.Allocator) !struct { mp.Map, mp.MapInfo, rl.Music } {
    log.debug("Downloading map", .{});

    const zipped = try webGet(url, allocator);
    defer allocator.free(zipped);

    try std.fs.cwd().deleteTree(target_path);
    try std.fs.cwd().writeFile(.{ .sub_path = target_filename, .data = zipped });
    try std.fs.cwd().makePath(target_path);

    log.debug("Unzipping map", .{});
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

    const map_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ target_path, map_filename });
    defer allocator.free(map_path);

    log.debug("Map path: '{s}'", .{map_path});

    const map_info_path = try std.fmt.allocPrint(allocator, "{s}/Info.dat", .{ target_path });
    defer allocator.free(map_info_path);

    const map_data = .{ try mp.parseFile(map_path, allocator), try mp.parseInfoFile(map_info_path, allocator), try ms.convertAndLoad(target_path, output_music_filename, allocator) };

    try std.fs.cwd().deleteTree(target_path);
    try std.fs.cwd().deleteFile(target_filename);

    return map_data;
}
