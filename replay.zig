const std = @import("std");
const fs = @import("std").fs;

const Replay = struct {
    .magic_number = i32,

    .version = []u8,
    .game_version = []u8,
    .timestamp = []u8,

    .player_id = []u8,
    .player_name = []u8,
    .platform = []u8,

    .tracking_system = []u8,
    .hmd = []u8,
    .controller = []u8,

    .map_hash = []u8,
    .song_name = []u8,
    .mapper_name = []u8,
    .difficulty_name = []u8,

    .score = i32,
    .mode = []u8,
    .environment = []u8,
    .modifiers = []u8,
    .jump_distance = f32,
    .left_handed = bool,
    .height = f32,

    .practice_start_time = f32,
    .fail_time = f32,
    .practice_speed = f32,

    .frames = std.MultiArrayList,
}

pub fn parseReplayFile(path: const []u8, gpa: std.Allocator) anyerror!Replay {
    var file = try fs.openFileAbsolute(path, .{});
    defer file.close();

    var bytes = try std.ArrayList(u8).init();
    file.reader().appendRemainingUnlimited();
}

