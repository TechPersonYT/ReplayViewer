const std = @import("std");
const NoteColor = @import("common.zig").NoteColor;
const CutDirection = @import("common.zig").CutDirection;

const MapVersion = struct {
    major: u8,
    minor: u8,
    revision: u8,
};

pub const Note = struct {
    time: f32 = 0.0,
    line_index: i32 = 0,
    line_layer: i32 = 0,
    color: NoteColor = .blue,
    cut_direction: CutDirection = .dot,
    angle_offset: ?i32 = null,
    rotation_lane: ?i32 = null,
};

pub const Bomb = struct {
    time: f32 = 0.0,
    line_index: i32 = 0,
    line_layer: i32 = 0,
    rotation_lane: ?i32 = null,
};

fn parseNote(version: MapVersion, note: std.json.ObjectMap) !Note {
    const time_field, const line_index_field, const line_layer_field, const color_field, const direction_field, const angle_field, const rotation_field = switch (version.major) {
        2 => .{ "_time", "_lineIndex", "_lineLayer", "_type", "_cutDirection", "_", "_" },
        3, 4 => .{ "b", "x", "y", "c", "d", "a", "r" },

        else => return error.UnknownMajorVersion,
    };

    return .{
        .time = getJsonNumber(f32, note, time_field) orelse 0.0,
        .line_index = getJsonNumber(i32, note, line_index_field) orelse 0,
        .line_layer = getJsonNumber(i32, note, line_layer_field) orelse 0,
        .color = getJsonEnum(NoteColor, note, color_field) orelse .blue,
        .cut_direction = getJsonEnum(CutDirection, note, direction_field) orelse .dot,
        .angle_offset = getJsonNumber(i32, note, angle_field),
        .rotation_lane = getJsonNumber(i32, note, rotation_field),
    };
}

fn parseBomb(version: MapVersion, note: std.json.ObjectMap) !Bomb {
    const time_field, const line_index_field, const line_layer_field, const rotation_field = switch (version.major) {
        2 => .{ "_time", "_lineIndex", "_lineLayer", "_" },
        3, 4 => .{ "b", "x", "y", "r" },

        else => return error.UnknownMajorVersion,
    };

    return .{
        .time = getJsonNumber(f32, note, time_field) orelse 0.0,
        .line_index = getJsonNumber(i32, note, line_index_field) orelse 0,
        .line_layer = getJsonNumber(i32, note, line_layer_field) orelse 0,
        .rotation_lane = getJsonNumber(i32, note, rotation_field),
    };
}

fn mergeNoteData(partial: Note, data: Note) Note {
    var result = data;

    result.time = partial.time;
    result.rotation_lane = partial.rotation_lane;

    return result;
}

fn mergeBombData(partial: Bomb, data: Bomb) Bomb {
    var result = data;

    result.time = partial.time;
    result.rotation_lane = partial.rotation_lane;

    return result;
}

fn isBombNote(value: std.json.ObjectMap) bool {
    if (value.get("_type")) |note_type| {
        switch (note_type) {
            .integer => |i| return @as(NoteColor, @enumFromInt(i)) == .legacy_bomb,
            else => return false,
        }
    } else return false;
}

fn getJsonArrayOrEmpty(map: std.json.ObjectMap, key: []const u8) []std.json.Value {
    if (map.get(key)) |value| {
        switch (value) {
            .array => |a| return a.items,
            else => {},
        }
    }

    return &.{};
}

fn getJsonNumber(T: type, map: std.json.ObjectMap, key: []const u8) ?T {
    return if (map.get(key)) |value| {
        return switch (value) {
            .integer => |number| std.math.lossyCast(T, number),
            .float => |number| std.math.lossyCast(T, number),
            else => null,
        };
    } else null;
}

fn getJsonEnum(T: type, map: std.json.ObjectMap, key: []const u8) ?T {
    return if (map.get(key)) |value| {
        return switch (value) {
            .integer => |number| @enumFromInt(number),
            else => null,
        };
    } else null;
}

fn parseNotes(root: std.json.ObjectMap, version: MapVersion, allocator: std.mem.Allocator) !std.MultiArrayList(Note) {
    var notes: std.MultiArrayList(Note) = .{};

    const notes_field, const data_field = switch (version.major) {
        2 => .{ "_notes", null },
        3 => .{ "colorNotes", null },
        4 => .{ "colorNotes", "colorNotesData" },

        else => return error.UnknownMajorVersion,
    };

    var notes_data: std.MultiArrayList(Note) = .{};
    defer notes_data.deinit(allocator);

    if (data_field) |field| {
        for (getJsonArrayOrEmpty(root, field)) |data| {
            switch (data) {
                .object => |d| try notes_data.append(allocator, try parseNote(version, d)),
                else => return error.InvalidJsonTypeForNote,
            }
        }
    }

    for (getJsonArrayOrEmpty(root, notes_field)) |note| {
        switch (note) {
            .object => |n| {
                if (isBombNote(n)) continue;

                const parsed = try parseNote(version, n);

                if (data_field) |_| {
                    const data = notes_data.get(getJsonNumber(usize, n, "i") orelse return error.NoIndexField);
                    try notes.append(allocator, mergeNoteData(parsed, data));
                } else {
                    try notes.append(allocator, parsed);
                }
            },
            else => return error.InvalidJsonTypeForNote,
        }
    }

    return notes;
}

fn parseBombs(root: std.json.ObjectMap, version: MapVersion, allocator: std.mem.Allocator) !std.MultiArrayList(Bomb) {
    var bombs: std.MultiArrayList(Bomb) = .{};

    const bombs_field, const data_field = switch (version.major) {
        2 => .{ "_bombs", null },
        3 => .{ "bombNotes", null },
        4 => .{ "bombNotes", "bombNotesData" },

        else => return error.UnknownMajorVersion,
    };

    var bombs_data: std.MultiArrayList(Bomb) = .{};
    defer bombs_data.deinit(allocator);

    if (data_field) |field| {
        for (getJsonArrayOrEmpty(root, field)) |data| {
            switch (data) {
                .object => |d| try bombs_data.append(allocator, try parseBomb(version, d)),
                else => return error.InvalidJsonTypeForBomb,
            }
        }
    }

    for (getJsonArrayOrEmpty(root, bombs_field)) |bomb| {
        switch (bomb) {
            .object => |b| {
                if (version.major == 2 and !isBombNote(b)) continue;

                const parsed = try parseBomb(version, b);

                if (data_field) |_| {
                    const data = bombs_data.get(getJsonNumber(usize, b, "i") orelse return error.NoIndexField);
                    try bombs.append(allocator, mergeBombData(parsed, data));
                } else {
                    try bombs.append(allocator, parsed);
                }
            },
            else => return error.InvalidJsonTypeForBomb,
        }
    }

    return bombs;
}

pub const Map = struct {
    notes: std.MultiArrayList(Note),
    bombs: std.MultiArrayList(Bomb),

    pub fn deinit(self: *Map, allocator: std.mem.Allocator) void {
        self.notes.deinit(allocator);
        self.bombs.deinit(allocator);
    }
};

pub fn parseMapFile(filename: []const u8, allocator: std.mem.Allocator) !Map {
    std.debug.print("Loading map\n", .{});

    const file = try std.fs.cwd().openFile(filename, .{});

    const buffer = try allocator.alloc(u8, try file.getEndPos() + 1);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return parseMap(buffer, allocator);
}

pub fn parseMapVersion(root: std.json.ObjectMap) ?MapVersion {
    const version = root.get("_version") orelse root.get("version") orelse return null;

    switch (version) {
        .string => |s| {
            const major = s[0] - '0';
            const minor = s[2] - '0';
            const revision = s[4] - '0';

            return .{ .major = major, .minor = minor, .revision = revision };
        },
        else => return null,
    }
}

pub fn parseMap(data: []const u8, allocator: std.mem.Allocator) !Map {
    const json = try std.json.parseFromSlice(std.json.Value, allocator, data[0 .. data.len - 1], .{});
    defer json.deinit();

    const root = json.value.object;
    const version = parseMapVersion(root) orelse return error.NoMapVersionFound;

    return .{ .notes = try parseNotes(root, version, allocator), .bombs = try parseBombs(root, version, allocator) };
}
