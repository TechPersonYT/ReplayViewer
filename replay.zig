const std = @import("std");
const fs = @import("std").fs;

const ReplayFrame = struct {
    .time = f32,
    .fps = i32,

    .head_position = rl.Vector3,
    .head_rotation = rl.Quaternion,

    .left_hand_position = rl.Vector3,
    .left_hand_rotation = rl.Quaternion,

    .right_hand_position = rl.Vector3,
    .right_hand_rotation = rl.Quaternion,
};

const ScoringType = enum {
    normal,
    ignore,
    no_score,
    normal2,
    slider_head,
    slider_tail,
    burst_slider_head,
    burst_slider_element,
};

const EventType = enum {
    good,
    bad,
    miss,
    bomb,
};

const SaberType = enum(i32) {
    left = 0,
    right = 1,
};

const CutInfo = struct {
    .speed_ok = bool,
    .direction_ok = bool,
    .saber_type_ok = bool,
    .too_soon = bool,
    .saber_speed = f32,
    .saber_direction = rl.Vector3,
    .saber_type = SaberType,
    .time_deviation = f32,
    .cut_direction_deviation = f32,
    .cut_point = rl.Vector3,
    .cut_normal = rl.Vector3,
    .cut_distance_to_center = f32,
    .cut_angle = f32,
    .before_cut_rating = f32,
    .after_cut_rating = f32,
};

const NoteEvent = struct {
    .scoring_type = ScoringType,
    .line_index = i32,
    .line_layer = i32,
    .color = NoteColor,
    .cut_direction = i32,
    .event_time = f32,
    .spawn_time = f32,
    .event_type = EventType,
    .cut_info = ?CutInfo,
};

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

    .frames = std.MultiArrayList(ReplayFrame),
    .notes = std.MultiArrayList(NoteEvent),
    .walls = []WallEvent,
    .heights = []HeightChangeEvent,
    .pauses = []PauseEvent,
    .user_data = []u8,
}

pub fn parseReplayFile(path: const []u8, gpa: std.Allocator) anyerror!Replay {
    var file = try fs.openFileAbsolute(path, .{});
    defer file.close();

    var bytes = try std.ArrayList(u8).init();
    file.reader().appendRemainingUnlimited();
}

