pub const NoteColor = enum(i32) {
    red,
    blue,
    legacy_bomb,

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

pub const Placement = struct {
    time: f32 = 0.0,
    x: f32 = 0.0,
    y: f32 = 0.0,
    rotation_lane: ?i32 = null,

    pub fn fromTxy(time: f32, x: f32, y: f32) Placement {
        return .{ .time = time, .x = x, .y = y };
    }

    pub fn fromTil(time: f32, line_index: i32, line_layer: i32) Placement {
        return .{
            .time = time,
            .x = 1.5 - @as(f32, @floatFromInt(line_index)),
            .y = 1.0 + @as(f32, @floatFromInt(line_layer)),
        };
    }

    pub fn fromTilr(time: f32, line_index: i32, line_layer: i32, rotation_lane: ?i32) Placement {
        return .{
            .time = time,
            .x = 1.5 - @as(f32, @floatFromInt(line_index)),
            .y = 1.0 + @as(f32, @floatFromInt(line_layer)),
            .rotation_lane = rotation_lane,
        };
    }
};
