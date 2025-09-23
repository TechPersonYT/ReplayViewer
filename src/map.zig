const std = @import("std");
const NoteColor = @import("common.zig").NoteColor;
const CutDirection = @import("common.zig").CutDirection;

const MapVersion = struct {
    major: u8,
    minor: u8,
    revision: u8,
};

pub const Note = struct {
    time: f32,
    line_index: i32 = 0,
    line_layer: i32 = 0,
    color: NoteColor = .blue,
    cut_direction: CutDirection = .dot,
    angle_offset: ?i32 = null,
    rotation_lane: ?i32 = null,
};

pub const Bomb = struct {
    time: f32,
    line_index: i32 = 0,
    line_layer: i32 = 0,
    rotation_lane: ?i32 = null,
};

fn isBomb(value: std.json.ObjectMap) bool {
    return @as(NoteColor, @enumFromInt(value.get("_type").?.integer)) == .legacy_bomb;
}

fn jsonToFloat(value: std.json.Value) f32 {
    return switch (value) {
        .integer => |v| @floatFromInt(v),
        .float => |v| @floatCast(v),
        else => @panic("Not a float or integer"),
    };
}

fn parseNotes(root: std.json.ObjectMap, version: MapVersion, allocator: std.mem.Allocator) !std.MultiArrayList(Note) {
    var notes: std.MultiArrayList(Note) = .{};

    switch (version.major) {
        2 => {
            for (root.get("_notes").?.array.items) |note| {
                const n = note.object;

                if (isBomb(n)) continue;

                try notes.append(allocator, .{
                    .time = jsonToFloat(n.get("_time").?),
                    .line_index = @intCast(n.get("_lineIndex").?.integer),
                    .line_layer = @intCast(n.get("_lineLayer").?.integer),
                    .color = @enumFromInt(n.get("_type").?.integer),
                    .cut_direction = @enumFromInt(n.get("_cutDirection").?.integer),
                });
            }
        },
        3 => {
            for (root.get("colorNotes").?.array.items) |note| {
                const n = note.object;

                try notes.append(allocator, .{
                    .time = jsonToFloat(n.get("b").?),
                    .line_index = @intCast(n.get("x").?.integer),
                    .line_layer = @intCast(n.get("y").?.integer),
                    .color = @enumFromInt(n.get("c").?.integer),
                    .cut_direction = @enumFromInt(n.get("d").?.integer),
                    .angle_offset = @intCast(n.get("a").?.integer),
                });
            }
        },
        4 => {
            // Get index data first
            var notes_data: std.MultiArrayList(Note) = .{};
            defer notes_data.deinit(allocator);

            for (root.get("colorNotesData").?.array.items) |data| {
                const d = data.object;

                try notes_data.append(allocator, .{
                    .time = undefined,
                    .line_index = @intCast(d.get("x").?.integer),
                    .line_layer = @intCast(d.get("y").?.integer),
                    .color = @enumFromInt(d.get("c").?.integer),
                    .cut_direction = @enumFromInt(d.get("d").?.integer),
                    .angle_offset = @intCast(d.get("a").?.integer),
                });
            }

            for (root.get("colorNotes").?.array.items) |note| {
                const n = note.object;
                const d = notes_data.get(@intCast(n.get("i").?.integer));

                try notes.append(allocator, .{
                    .time = jsonToFloat(n.get("b").?),
                    .line_index = d.line_index,
                    .line_layer = d.line_layer,
                    .color = d.color,
                    .cut_direction = d.cut_direction,
                    .angle_offset = d.angle_offset,
                    .rotation_lane = @intCast(n.get("r").?.integer),
                });
            }
        },
        else => return error.UnknownMajorVersion,
    }

    return notes;
}

fn parseBombs(root: std.json.ObjectMap, version: MapVersion, allocator: std.mem.Allocator) !std.MultiArrayList(Bomb) {
    var bombs: std.MultiArrayList(Bomb) = .{};

    switch (version.major) {
        2 => {
            for (root.get("_notes").?.array.items) |bomb| {
                const b = bomb.object;

                if (isBomb(b)) {
                    try bombs.append(allocator, .{
                        .time = jsonToFloat(b.get("_time").?),
                        .line_index = @intCast(b.get("_lineIndex").?.integer),
                        .line_layer = @intCast(b.get("_lineLayer").?.integer),
                    });
                }
            }
        },
        3 => {
            for (root.get("bombNotes").?.array.items) |bomb| {
                const b = bomb.object;

                try bombs.append(allocator, .{
                    .time = jsonToFloat(b.get("b").?),
                    .line_index = @intCast(b.get("x").?.integer),
                    .line_layer = @intCast(b.get("y").?.integer),
                });
            }
        },
        4 => {
            // Get index data first
            var bombs_data: std.MultiArrayList(Bomb) = .{};
            defer bombs_data.deinit(allocator);

            for (root.get("bombNotesData").?.array.items) |data| {
                const d = data.object;

                try bombs_data.append(allocator, .{
                    .time = undefined,
                    .line_index = @intCast(d.get("x").?.integer),
                    .line_layer = @intCast(d.get("y").?.integer),
                });
            }

            for (root.get("bombNotes").?.array.items) |bomb| {
                const b = bomb.object;
                const d = bombs_data.get(@intCast(b.get("i").?.integer));

                try bombs.append(allocator, .{
                    .time = @floatFromInt(b.get("b").?.integer),
                    .line_index = d.line_index,
                    .line_layer = d.line_layer,
                    .rotation_lane = @intCast(b.get("r").?.integer),
                });
            }
        },
        else => return error.UnknownMajorVersion,
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

pub fn parseMapVersion(root: std.json.ObjectMap) MapVersion {
    const string = (root.get("_version") orelse root.get("version").?).string;

    const major = string[0] - '0';
    const minor = string[2] - '0';
    const revision = string[4] - '0';

    return .{ .major = major, .minor = minor, .revision = revision };
}

pub fn parseMap(data: []const u8, allocator: std.mem.Allocator) !Map {
    std.debug.print("{s}\n", .{data});
    const json = try std.json.parseFromSlice(std.json.Value, allocator, data[0 .. data.len - 1], .{});
    defer json.deinit();

    const root = json.value.object;
    const version = parseMapVersion(root);

    return .{ .notes = try parseNotes(root, version, allocator), .bombs = try parseBombs(root, version, allocator) };
}
