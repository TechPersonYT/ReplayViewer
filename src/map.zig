const std = @import("std");
const log = std.log.scoped(.map);
const NoteColor = @import("common.zig").NoteColor;
const CutDirection = @import("common.zig").CutDirection;

const Version = struct {
    major: u8,
    minor: u8,
    revision: u8,
};

pub const Placement = struct {
    time: f32 = 0.0,
    line_index: i32 = 0,
    line_layer: i32 = 0,
    rotation_lane: ?i32 = null,
};

pub const Note = struct {
    placement: Placement,
    color: NoteColor = .blue,
    cut_direction: CutDirection = .dot,
    angle_offset: ?i32 = null,
};

pub const Bomb = struct {
    placement: Placement,
};

pub const LegacyWallType = enum {
    full_height,
    crouch,
    free,
};

pub const Wall = struct {
    placement: Placement,
    width: i32 = 1,
    height: i32 = 1,
    duration: f32 = 1.0,
};

fn parsePlacement(version: Version, object: std.json.ObjectMap) !Placement {
    const time_field, const line_index_field, const line_layer_field, const rotation_field = switch (version.major) {
        2 => .{ "_time", "_lineIndex", "_lineLayer", "_" },
        3, 4 => .{ "b", "x", "y", "r" },

        else => return error.UnknownMajorVersion,
    };

    return .{
        .time = getJsonNumber(f32, object, time_field) orelse 0.0,
        .line_index = getJsonNumber(i32, object, line_index_field) orelse 0,
        .line_layer = getJsonNumber(i32, object, line_layer_field) orelse 0,
        .rotation_lane = getJsonNumber(i32, object, rotation_field),
    };
}

fn parseNote(version: Version, note: std.json.ObjectMap) !Note {
    const color_field, const direction_field, const angle_field = switch (version.major) {
        2 => .{
            "_type",
            "_cutDirection",
            "_",
        },
        3, 4 => .{ "c", "d", "a" },

        else => return error.UnknownMajorVersion,
    };

    return .{
        .placement = try parsePlacement(version, note),
        .color = getJsonEnum(NoteColor, note, color_field) orelse .blue,
        .cut_direction = getJsonEnum(CutDirection, note, direction_field) orelse .dot,
        .angle_offset = getJsonNumber(i32, note, angle_field),
    };
}

fn parseBomb(version: Version, bomb: std.json.ObjectMap) !Bomb {
    return .{ .placement = try parsePlacement(version, bomb) };
}

fn parseWall(version: Version, wall: std.json.ObjectMap) !Wall {
    switch (version.major) {
        2 => switch (version.minor) {
            0...5 => {
                const time = getJsonNumber(f32, wall, "_time") orelse 0.0;
                const line_index = getJsonNumber(i32, wall, "_lineIndex") orelse 0;

                const wall_type = getJsonEnum(LegacyWallType, wall, "_type") orelse return error.BadLegacyWallType;

                const line_layer = switch (wall_type) {
                    .full_height => 0,
                    .crouch => 2,
                    .free => getJsonNumber(i32, wall, "_lineLayer") orelse return error.NoWallLineLayer,
                };

                const width = getJsonNumber(i32, wall, "_width") orelse 1;

                const height = switch (wall_type) {
                    .full_height => 5,
                    .crouch => 3,
                    .free => getJsonNumber(i32, wall, "_height") orelse return error.NoWallHeight,
                };

                const duration = getJsonNumber(f32, wall, "_duration") orelse 1.0;

                return .{
                    .placement = .{
                        .time = time,
                        .line_index = line_index,
                        .line_layer = line_layer,
                    },
                    .width = width,
                    .height = height,
                    .duration = duration,
                };
            },
            6...9 => {},

            else => error.UnknownMinorVersion,
        },
    }
}

fn mergeNoteData(partial: Note, data: Note) Note {
    var result = data;

    result.placement.time = partial.placement.time;
    result.placement.rotation_lane = partial.placement.rotation_lane;

    return result;
}

fn mergeBombData(partial: Bomb, data: Bomb) Bomb {
    var result = data;

    result.placement.time = partial.placement.time;
    result.placement.rotation_lane = partial.placement.rotation_lane;

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

fn parseNotes(root: std.json.ObjectMap, version: Version, allocator: std.mem.Allocator) !std.MultiArrayList(Note) {
    log.debug("Parsing map notes", .{});

    var notes: std.MultiArrayList(Note) = .{};
    errdefer notes.deinit(allocator);

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

    log.debug("Parsed {} notes", .{notes.len});

    return notes;
}

fn parseBombs(root: std.json.ObjectMap, version: Version, allocator: std.mem.Allocator) !std.MultiArrayList(Bomb) {
    log.debug("Parsing map bombs", .{});

    var bombs: std.MultiArrayList(Bomb) = .{};
    errdefer bombs.deinit(allocator);

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

    log.debug("Parsed {} bombs", .{bombs.len});

    return bombs;
}

// TODO: Parse walls

fn parseJumpSpeeds(root: std.json.ObjectMap, version: Version, allocator: std.mem.Allocator) !std.ArrayList(f32) {
    var speeds: std.ArrayList(f32) = .empty;

    errdefer speeds.deinit(allocator);

    switch (version.major) {
        2 => {
            const sets = getJsonArrayOrEmpty(root, "_difficultyBeatmapSets");

            for (sets) |set| {
                switch (set) {
                    .object => |s| {
                        const maps = getJsonArrayOrEmpty(s, "_difficultyBeatmaps");

                        for (maps) |map| {
                            switch (map) {
                                .object => |o| try speeds.append(allocator, getJsonNumber(f32, o, "_noteJumpMovementSpeed") orelse return error.NoV2JumpMovementSpeed),
                                else => return error.UnexpectedMapType,
                            }
                        }
                    },
                    else => return error.UnexpectedSetType,
                }
            }
        },
        4 => {
            const sets = getJsonArrayOrEmpty(root, "difficultyBeatmaps");

            for (sets) |set| {
                switch (set) {
                    .object => |s| {
                        try speeds.append(allocator, getJsonNumber(f32, s, "noteJumpMovementSpeed") orelse return error.NoV4JumpMovementSpeed);
                    },
                    else => return error.UnexpectedSetType,
                }
            }
        },
        else => return error.InvalidMapInfoVersion,
    }

    return speeds;
}

pub const Map = struct {
    notes: std.MultiArrayList(Note),
    bombs: std.MultiArrayList(Bomb),

    pub fn deinit(self: *Map, allocator: std.mem.Allocator) void {
        log.debug("Map.deinit()", .{});
        self.notes.deinit(allocator);
        self.bombs.deinit(allocator);
    }
};

pub const MapInfo = struct {
    jump_speeds: std.ArrayList(f32),

    pub fn deinit(self: *MapInfo, allocator: std.mem.Allocator) void {
        log.debug("MapInfo.deinit()", .{});
        self.jump_speeds.deinit(allocator);
    }
};

pub fn parseFile(filename: []const u8, allocator: std.mem.Allocator) !Map {
    log.debug("Parsing map file '{s}'", .{filename});

    const file = try std.fs.cwd().openFile(filename, .{});

    const buffer = try allocator.alloc(u8, try file.getEndPos() + 1);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return parse(buffer, allocator);
}

pub fn parseInfoFile(filename: []const u8, allocator: std.mem.Allocator) !MapInfo {
    log.debug("Parsing map info file '{s}'", .{filename});

    const file = try std.fs.cwd().openFile(filename, .{});

    const buffer = try allocator.alloc(u8, try file.getEndPos() + 1);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return parseInfo(buffer, allocator);
}

pub fn parseVersion(root: std.json.ObjectMap) ?Version {
    log.debug("Parsing map version", .{});

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

pub fn parse(data: []const u8, allocator: std.mem.Allocator) !Map {
    log.debug("Parsing map ({} bytes)", .{data.len});
    const json = try std.json.parseFromSlice(std.json.Value, allocator, data[0 .. data.len - 1], .{});
    defer json.deinit();

    const root = json.value.object;
    const version = parseVersion(root) orelse return error.NoVersionFound;

    return .{ .notes = try parseNotes(root, version, allocator), .bombs = try parseBombs(root, version, allocator) };
}

pub fn parseInfo(data: []const u8, allocator: std.mem.Allocator) !MapInfo {
    log.debug("Parsing map info ({} bytes)", .{data.len});
    const json = try std.json.parseFromSlice(std.json.Value, allocator, data[0 .. data.len - 1], .{});
    defer json.deinit();

    const root = json.value.object;
    const version = parseVersion(root) orelse return error.NoVersionFound;

    return .{ .jump_speeds = try parseJumpSpeeds(root, version, allocator) };
}
