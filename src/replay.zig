const std = @import("std");
const fs = @import("std").fs;

const rl = @import("raylib");

pub const ReplayFrame = struct {
    time: f32,
    fps: i32,

    head_position: rl.Vector3,
    head_rotation: rl.Quaternion,

    left_hand_position: rl.Vector3,
    left_hand_rotation: rl.Quaternion,

    right_hand_position: rl.Vector3,
    right_hand_rotation: rl.Quaternion,
};

pub const ScoringType = enum {
    normal,
    ignore,
    no_score,
    normal2,
    slider_head,
    slider_tail,
    burst_slider_head,
    burst_slider_element,
};

pub const EventType = enum {
    good,
    bad,
    miss,
    bomb,
};

pub const SaberType = enum(i32) {
    left = 0,
    right = 1,
};

pub const NoteColor = enum(i32) {
    red = 0,
    blue = 1,
};

pub const ObstacleType = enum(i32) {
    // ???
};

pub const CutInfo = struct {
    speed_ok: bool,
    direction_ok: bool,
    saber_type_ok: bool,
    too_soon: bool,
    saber_speed: f32,
    saber_direction: rl.Vector3,
    saber_type: SaberType,
    time_deviation: f32,
    cut_direction_deviation: f32,
    cut_point: rl.Vector3,
    cut_normal: rl.Vector3,
    cut_distance_to_center: f32,
    cut_angle: f32,
    before_cut_rating: f32,
    after_cut_rating: f32,
};

pub const NoteEvent = struct {
    scoring_type: ScoringType,
    line_index: i32,
    line_layer: i32,
    color: NoteColor,
    cut_direction: i32,
    event_time: f32,
    spawn_time: f32,
    event_type: EventType,
    cut_info: ?CutInfo,
};

pub const WallEvent = struct {
    line_index: i32,
    obstacle_type: ObstacleType,
    width: i32,
    energy: f32,
    time: f32,
    spawn_time: f32,
};

pub const HeightChangeEvent = struct {
    height: f32,
    time: f32,
};

pub const PauseEvent = struct {
    duration: f32,
    time: f32,
};

pub const ControllerOffsets = struct {
    left_hand_offset: rl.Vector3,
    left_hand_offset_rotation: rl.Quaternion,

    right_hand_offset: rl.Vector3,
    right_hand_offset_rotation: rl.Quaternion,
};

pub const Replay = struct {
    magic_number: i32,
    file_version: u8,

    mod_version: []u8,
    game_version: []u8,
    timestamp: []u8,

    player_id: []u8,
    player_name: []u8,
    platform: []u8,

    tracking_system: []u8,
    hmd: []u8,
    controller: []u8,

    map_hash: []u8,
    song_name: []u8,
    mapper_name: []u8,
    difficulty_name: []u8,

    score: i32,
    game_mode: []u8,
    environment: []u8,
    modifiers: []u8,
    jump_distance: f32,
    left_handed: bool,
    height: f32,

    practice_start_time: f32,
    fail_time: f32,
    practice_speed: f32,

    frames: std.MultiArrayList(ReplayFrame),
    notes: std.MultiArrayList(NoteEvent),
    walls: []WallEvent,
    heights: []HeightChangeEvent,
    pauses: []PauseEvent,
    offsets: ?ControllerOffsets,
    user_data: ?[]u8,

    pub fn dump_info(self: *const Replay) void {
        std.debug.print("Mod version: {s}\n", .{self.mod_version});
        std.debug.print("Game version: {s}\n", .{self.game_version});
        std.debug.print("Timestamp: {s}\n", .{self.timestamp});
        std.debug.print("Player id: {s}\n", .{self.player_id});
        std.debug.print("Player name: {s}\n", .{self.player_name});
        std.debug.print("Platform: {s}\n", .{self.platform});
        std.debug.print("Tracking system: {s}\n", .{self.tracking_system});
        std.debug.print("Hmd: {s}\n", .{self.hmd});
        std.debug.print("Controller: {s}\n", .{self.controller});
        std.debug.print("Map hash: {s}\n", .{self.map_hash});
        std.debug.print("Song name: {s}\n", .{self.song_name});
        std.debug.print("Mapper name: {s}\n", .{self.mapper_name});
        std.debug.print("Difficulty name: {s}\n", .{self.difficulty_name});
        std.debug.print("Score: {}\n", .{self.score});
        std.debug.print("Game mode: {s}\n", .{self.game_mode});
        std.debug.print("Environment: {s}\n", .{self.environment});
        std.debug.print("Modifiers: {s}\n", .{self.modifiers});
        std.debug.print("Jump distance: {}\n", .{self.jump_distance});
        std.debug.print("Left handed: {}\n", .{self.left_handed});
        std.debug.print("Height: {}\n", .{self.height});
        std.debug.print("Practice start time: {}\n", .{self.practice_start_time});
        std.debug.print("Fail time: {}\n", .{self.fail_time});
        std.debug.print("Practice speed: {}\n", .{self.practice_speed});
    }

    pub fn deinit(self: *Replay, gpa: std.mem.Allocator) void {
        gpa.free(self.mod_version);
        gpa.free(self.game_version);
        gpa.free(self.timestamp);
        gpa.free(self.player_id);
        gpa.free(self.player_name);
        gpa.free(self.platform);
        gpa.free(self.tracking_system);
        gpa.free(self.hmd);
        gpa.free(self.controller);
        gpa.free(self.map_hash);
        gpa.free(self.song_name);
        gpa.free(self.mapper_name);
        gpa.free(self.difficulty_name);
        gpa.free(self.game_mode);
        gpa.free(self.environment);
        gpa.free(self.modifiers);
        //gpa.free(self.frames);
        //gpa.free(self.notes);
        //gpa.free(self.walls);
        //gpa.free(self.heights);
        //gpa.free(self.pauses);
        //gpa.free(self.offsets);
        //gpa.free(self.user_data);
    }
};

fn takeString(reader: *std.Io.Reader, gpa: std.mem.Allocator) ![]u8 {
    const length = @as(u32, @intCast(try reader.takeInt(i32, .little)));
    const buffer = try gpa.alloc(u8, length);

    @memcpy(buffer, try reader.take(length));

    return buffer;
}

fn takeFloat(reader: *std.Io.Reader) !f32 {
    return @as(f32, @bitCast(try reader.takeInt(i32, .little)));
}

fn takeInt(reader: *std.Io.Reader) !i32 {
    return reader.takeInt(i32, .little);
}

fn takeByte(reader: *std.Io.Reader) !u8 {
    return reader.takeByte();
}

fn takeBool(reader: *std.Io.Reader) !bool {
    return @as(u8, @bitCast(try reader.takeByte())) != 0;
}

pub fn parseReplayFile(path: []const u8, gpa: std.mem.Allocator) !Replay {
    var file = try fs.openFileAbsolute(path, .{});
    defer file.close();

    // Buffer the entire file
    const buffer: []u8 = try gpa.alloc(u8, try file.getEndPos());
    defer gpa.free(buffer);
    var reader = file.reader(buffer);
    var replay: Replay = undefined;

    replay.magic_number = try takeInt(&reader.interface);
    replay.file_version = try takeByte(&reader.interface);

    // Info section
    if (try takeByte(&reader.interface) != 0) {
        return error.InvalidSectionStartByte;
    }

    replay.mod_version     =     try takeString(&reader.interface, gpa);
    replay.game_version    =     try takeString(&reader.interface, gpa);
    replay.timestamp       =     try takeString(&reader.interface, gpa);
    replay.player_id       =     try takeString(&reader.interface, gpa);
    replay.player_name     =     try takeString(&reader.interface, gpa);
    replay.platform        =     try takeString(&reader.interface, gpa);
    replay.tracking_system =     try takeString(&reader.interface, gpa);
    replay.hmd             =     try takeString(&reader.interface, gpa);
    replay.controller      =     try takeString(&reader.interface, gpa);
    replay.map_hash        =     try takeString(&reader.interface, gpa);
    replay.song_name       =     try takeString(&reader.interface, gpa);
    replay.mapper_name     =     try takeString(&reader.interface, gpa);
    replay.difficulty_name =     try takeString(&reader.interface, gpa);

    replay.score           =     try takeInt(&reader.interface);

    replay.game_mode       =     try takeString(&reader.interface, gpa);
    replay.environment     =     try takeString(&reader.interface, gpa);
    replay.modifiers       =     try takeString(&reader.interface, gpa);

    replay.jump_distance =       try takeFloat(&reader.interface);
    replay.left_handed =         try takeBool(&reader.interface);
    replay.height =              try takeFloat(&reader.interface);

    replay.practice_start_time = try takeFloat(&reader.interface);
    replay.fail_time =           try takeFloat(&reader.interface);
    replay.practice_speed =      try takeFloat(&reader.interface);

    // TODO: Other sections

    return replay;
}

