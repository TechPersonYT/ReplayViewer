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
