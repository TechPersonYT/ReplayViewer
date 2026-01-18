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
    line_index: i32 = 0,
    line_layer: i32 = 0,
    rotation_lane: ?i32 = null,
};
