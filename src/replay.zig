const std = @import("std");
const fs = @import("std").fs;

const rl = @import("raylib");

const ReplayFileSection = enum(u8) {
    info,
    frames,
    notes,
    walls,
    heights,
    pauses,
    controller_offsets,
    user_data,

    _,
};

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

pub const ScoringType = enum(i32) {
    normal,
    ignore,
    no_score,
    normal2,
    slider_head,
    slider_tail,
    burst_slider_head,
    burst_slider_element,

    _,
};

pub const EventType = enum(i32) {
    good,
    bad,
    miss,
    bomb,

    _,
};

pub const SaberType = enum(i32) {
    left,
    right,

    _,
};

pub const NoteColor = enum(i32) {
    red,
    blue,

    _,
};

pub const CutDirection = enum(i32) {
    up,
    down,
    left,
    right,
    up_left,
    up_right,
    down_left,
    down_right,
    dot,

    _,
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
    cut_direction: CutDirection,
    event_time: f32,
    spawn_time: f32,
    event_type: EventType,
    cut_info: ?CutInfo,
};

pub const WallEvent = struct {
    line_index: i32,
    obstacle_type: i32,
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
    duration: i64,
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
    walls: std.MultiArrayList(WallEvent),
    heights: std.MultiArrayList(HeightChangeEvent),
    pauses: std.MultiArrayList(PauseEvent),
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
        self.frames.deinit(gpa);
        self.notes.deinit(gpa);
        self.walls.deinit(gpa);
        self.heights.deinit(gpa);
        self.pauses.deinit(gpa);

        if (self.user_data) |data| {
            gpa.free(data);
        }
    }
};

fn getSection(reader: *std.Io.Reader) !ReplayFileSection {
    return @enumFromInt(try takeByte(reader));
}

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

fn takeLong(reader: *std.Io.Reader) !i64 {
    return reader.takeInt(i64, .little);
}

fn takeByte(reader: *std.Io.Reader) !u8 {
    return reader.takeByte();
}

fn takeBool(reader: *std.Io.Reader) !bool {
    return @as(u8, @bitCast(try reader.takeByte())) != 0;
}

fn takeVector(reader: *std.Io.Reader) !rl.Vector3 {
    return .{
        .x = try takeFloat(reader),
        .y = try takeFloat(reader),
        .z = try takeFloat(reader),
    };
}

fn takeQuaternion(reader: *std.Io.Reader) !rl.Quaternion {
    return .{
        .x = try takeFloat(reader),
        .y = try takeFloat(reader),
        .z = try takeFloat(reader),
        .w = try takeFloat(reader),
    };
}

fn takeFrame(reader: *std.Io.Reader) !ReplayFrame {
    return .{
        .time = try takeFloat(reader),
        .fps = try takeInt(reader),

        .head_position = try takeVector(reader),
        .head_rotation = try takeQuaternion(reader),

        .left_hand_position = try takeVector(reader),
        .left_hand_rotation = try takeQuaternion(reader),

        .right_hand_position = try takeVector(reader),
        .right_hand_rotation = try takeQuaternion(reader),
    };
}

fn takeCutInfo(reader: *std.Io.Reader) !CutInfo {
    return .{
        .speed_ok = try takeBool(reader),
        .direction_ok = try takeBool(reader),
        .saber_type_ok = try takeBool(reader),
        .too_soon = try takeBool(reader),
        .saber_speed = try takeFloat(reader),
        .saber_direction = try takeVector(reader),
        .saber_type = @enumFromInt(try takeInt(reader)),
        .time_deviation = try takeFloat(reader),
        .cut_direction_deviation = try takeFloat(reader),
        .cut_point = try takeVector(reader),
        .cut_normal = try takeVector(reader),
        .cut_distance_to_center = try takeFloat(reader),
        .cut_angle = try takeFloat(reader),
        .before_cut_rating = try takeFloat(reader),
        .after_cut_rating = try takeFloat(reader),
    };
}

fn takeNoteEvent(reader: *std.Io.Reader) !NoteEvent {
    var note_info = try takeInt(reader);

    const direction = @rem(note_info, 10);
    note_info = @divTrunc(note_info, 10);

    const color = @rem(note_info, 10);
    note_info = @divTrunc(note_info, 10);

    const line_layer = @rem(note_info, 10);
    note_info = @divTrunc(note_info, 10);

    const line_index = @rem(note_info, 10);
    note_info = @divTrunc(note_info, 10);

    const scoring_type = @rem(note_info, 10);

    const event_time = try takeFloat(reader);
    const spawn_time = try takeFloat(reader);
    const event_type: EventType = @enumFromInt(try takeInt(reader));

    return .{
        .scoring_type = @enumFromInt(scoring_type),
        .line_index = line_index,
        .line_layer = line_layer,
        .color = @enumFromInt(color),
        .cut_direction = @enumFromInt(direction),
        .event_time = event_time,
        .spawn_time = spawn_time,
        .event_type = event_type,
        .cut_info = switch (event_type) { .good, .bad => try takeCutInfo(reader), else => null },
    };
}

fn takeWallEvent(reader: *std.Io.Reader) !WallEvent {
    var wall_info = try takeInt(reader);

    const line_index = @rem(wall_info, 10);
    wall_info = @divTrunc(wall_info, 10);

    const obstacle_type = @rem(wall_info, 10);
    wall_info = @divTrunc(wall_info, 10);

    const width = @rem(wall_info, 10);
    wall_info = @divTrunc(wall_info, 10);

    return .{
        .line_index = line_index,
        .obstacle_type = obstacle_type,
        .width = width,
        .energy = try takeFloat(reader),
        .time = try takeFloat(reader),
        .spawn_time = try takeFloat(reader),
    };
}

fn takeHeightEvent(reader: *std.Io.Reader) !HeightChangeEvent {
    return .{ .height = try takeFloat(reader), .time = try takeFloat(reader) };
}

fn takePauseEvent(reader: *std.Io.Reader) !PauseEvent {
    return .{ .duration = try takeLong(reader), .time = try takeFloat(reader) };
}

fn takeArray(T: type, reader: *std.Io.Reader, gpa: std.mem.Allocator, parseFunction: fn (r: *std.Io.Reader) anyerror!T) !std.MultiArrayList(T) {
    var array: std.MultiArrayList(T) = .{};
    const capacity: usize = @intCast(try takeInt(reader));
    try array.setCapacity(gpa, capacity);

    for (0..capacity) |_| {
        array.appendAssumeCapacity(try parseFunction(reader));
    }

    return array;
}

fn takeOffsets(reader: *std.Io.Reader) !ControllerOffsets {
    return .{
        .left_hand_offset = try takeVector(reader),
        .left_hand_offset_rotation = try takeQuaternion(reader),

        .right_hand_offset = try takeVector(reader),
        .right_hand_offset_rotation = try takeQuaternion(reader),
    };
}

pub fn parseReplayFile(filename: []const u8, gpa: std.mem.Allocator) !Replay {
    const file = try std.fs.cwd().openFile(filename, .{});

    const buffer = try gpa.alloc(u8, try file.getEndPos() + 1);
    defer gpa.free(buffer);

    var reader = file.reader(buffer).interface;

    return parseReplay(&reader, gpa);
}

pub fn parseReplay(reader: *std.Io.Reader, gpa: std.mem.Allocator) !Replay {
    var replay: Replay = undefined;
    replay.offsets = null;
    replay.user_data = null;

    replay.magic_number = try takeInt(reader);
    replay.file_version = try takeByte(reader);

    // Info section
    if (try getSection(reader) != .info) {
        return error.InvalidSectionStartByte;
    }

    replay.mod_version     =     try takeString(reader, gpa);
    replay.game_version    =     try takeString(reader, gpa);
    replay.timestamp       =     try takeString(reader, gpa);
    replay.player_id       =     try takeString(reader, gpa);
    replay.player_name     =     try takeString(reader, gpa);
    replay.platform        =     try takeString(reader, gpa);
    replay.tracking_system =     try takeString(reader, gpa);
    replay.hmd             =     try takeString(reader, gpa);
    replay.controller      =     try takeString(reader, gpa);
    replay.map_hash        =     try takeString(reader, gpa);
    replay.song_name       =     try takeString(reader, gpa);
    replay.mapper_name     =     try takeString(reader, gpa);
    replay.difficulty_name =     try takeString(reader, gpa);

    replay.score           =     try takeInt(reader);

    replay.game_mode       =     try takeString(reader, gpa);
    replay.environment     =     try takeString(reader, gpa);
    replay.modifiers       =     try takeString(reader, gpa);

    replay.jump_distance =       try takeFloat(reader);
    replay.left_handed =         try takeBool(reader);
    replay.height =              try takeFloat(reader);

    replay.practice_start_time = try takeFloat(reader);
    replay.fail_time =           try takeFloat(reader);
    replay.practice_speed =      try takeFloat(reader);

    inline for (.{ &replay.frames, &replay.notes, &replay.walls, &replay.heights  , &replay.pauses },
                .{ .frames       , .notes       , .walls       , .heights         , .pauses },
                .{ ReplayFrame   , NoteEvent    , WallEvent    , HeightChangeEvent, PauseEvent },
                .{ takeFrame     , takeNoteEvent, takeWallEvent, takeHeightEvent  , takePauseEvent} ) |array, section, ItemType, parseFunction| {
        if (try getSection(reader) != section) {
            return error.InvalidSectionStartByte;
        }

        array.* = try takeArray(ItemType, reader, gpa, parseFunction);
    }

//    // Frames section
//    if (try getSection(reader) != .frames) {
//        return error.InvalidSectionStartByte;
//    }
//
//    replay.frames = try takeArray(ReplayFrame, reader, gpa, takeFrame);
//
//    // Notes section
//    if (try getSection(reader) != .notes) {
//        return error.InvalidSectionStartByte;
//    }
//
//    replay.notes = try takeArray(NoteEvent, reader, gpa, takeNoteEvent);
//
//    // Walls section
//    if (try getSection(reader) != .walls) {
//        return error.InvalidSectionStartByte;
//    }
//
//    replay.walls = try takeArray(WallEvent, reader, gpa, takeWallEvent);
//
//    // Heights section
//    if (try getSection(reader) != .heights) {
//        return error.InvalidSectionStartByte;
//    }
//
//    replay.heights = try takeArray(HeightChangeEvent, reader, gpa, takeHeightEvent);
//
//    // Pauses section
//    if (try getSection(reader) != .pauses) {
//        return error.InvalidSectionStartByte;
//    }
//
//    replay.pauses = try takeArray(PauseEvent, reader, gpa, takePauseEvent);
//
    // Offsets section (optional)
    if (getSection(reader) catch .frames == .controller_offsets) {
        replay.offsets = try takeOffsets(reader);
    }

    // User data section (optional)
    if (getSection(reader) catch .frames == .user_data) {
        replay.user_data = try takeString(reader, gpa);
    }

    return replay;
}

