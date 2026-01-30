const std = @import("std");
const log = std.log.scoped(.map);
const NoteColor = @import("common.zig").NoteColor;
const CutDirection = @import("common.zig").CutDirection;
const Placement = @import("common.zig").Placement;

const Version = struct {
    major: u8,
    minor: u8,
    revision: u8,
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

    const time = getJsonNumber(f32, object, time_field) orelse 0.0;
    const line_index = getJsonNumber(i32, object, line_index_field) orelse 0;
    const line_layer = getJsonNumber(i32, object, line_layer_field) orelse 0;
    const rotation_lane = getJsonNumber(i32, object, rotation_field);

    return Placement.fromTilr(time, line_index, line_layer, rotation_lane);
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

fn getJsonString(map: std.json.ObjectMap, key: []const u8, allocator: std.mem.Allocator) !?[]u8 {
    return if (map.get(key)) |value| {
        return switch (value) {
            .string => |string| return try allocator.dupe(u8, string),
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

pub const Map = struct {
    notes: std.MultiArrayList(Note),
    bombs: std.MultiArrayList(Bomb),

    pub fn deinit(self: *Map, allocator: std.mem.Allocator) void {
        log.debug("Map.deinit()", .{});
        self.notes.deinit(allocator);
        self.bombs.deinit(allocator);
    }
};

pub const DifficultyRank = enum(u8) {
    Easy = 1,
    Normal = 3,
    Hard = 5,
    Expert = 7,
    ExpertPlus = 9,
    _,

    pub fn fromString(s: []const u8) DifficultyRank {
        if (std.mem.eql(u8, s, "Easy")) return .Easy;
        if (std.mem.eql(u8, s, "Normal")) return .Normal;
        if (std.mem.eql(u8, s, "Hard")) return .Hard;
        if (std.mem.eql(u8, s, "Expert")) return .Expert;
        if (std.mem.eql(u8, s, "ExpertPlus")) return .ExpertPlus;

        return .ExpertPlus;
    }
};

pub const MapCharacteristic = enum {
    Standard,
    NoArrows,
    OneSaber,
    ThreeSixtyDegree,
    NinetyDegree,
    Legacy,

    Unknown,

    pub fn fromString(s: []const u8) MapCharacteristic {
        if (std.mem.eql(u8, s, "Standard")) return .Standard;
        if (std.mem.eql(u8, s, "NoArrows")) return .NoArrows;
        if (std.mem.eql(u8, s, "OneSaber")) return .OneSaber;
        if (std.mem.eql(u8, s, "360Degree")) return .ThreeSixtyDegree;
        if (std.mem.eql(u8, s, "90Degree")) return .NinetyDegree;
        if (std.mem.eql(u8, s, "Legacy")) return .Legacy;

        return .Unknown;
    }
};

pub const DifficultyInfo = struct {
    filename: []u8,
    characteristic: MapCharacteristic,
    rank: ?DifficultyRank,
    mappers: std.ArrayList([]u8),
    lighters: std.ArrayList([]u8),
    njs: f32,
    nso: f32,

    pub fn deinit(self: *DifficultyInfo, allocator: std.mem.Allocator) void {
        log.debug("DifficultyInfo.deinit()", .{});
        allocator.free(self.filename);

        for (self.mappers.items) |mapper| {
            allocator.free(mapper);
        }

        self.mappers.deinit(allocator);

        for (self.lighters.items) |lighter| {
            allocator.free(lighter);
        }

        self.lighters.deinit(allocator);
    }
};

pub const MapInfo = struct {
    song_title: []u8,
    song_subtitle: []u8,
    song_author: []u8,
    song_filename: []u8,
    cover_image_filename: []u8,
    bpm: f32,
    lufs: ?f32 = null,
    duration: ?f32 = null,

    // Deprecated in v4 (thank goodness); rather than support these properly we throw a big fat warning
    song_time_offset: ?f32 = null,
    shuffle: ?f32 = null,
    shuffle_period: ?f32 = null,

    difficulties: std.ArrayList(DifficultyInfo),

    pub fn deinit(self: *MapInfo, allocator: std.mem.Allocator) void {
        log.debug("MapInfo.deinit()", .{});
        allocator.free(self.song_title);
        allocator.free(self.song_subtitle);
        allocator.free(self.song_author);
        allocator.free(self.song_filename);
        allocator.free(self.cover_image_filename);

        for (self.difficulties.items) |*difficulty| {
            difficulty.deinit(allocator);
        }

        self.difficulties.deinit(allocator);
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

    return switch (version.major) {
        2 => outer: {
            const song_title = try getJsonString(root, "_songName", allocator) orelse return error.NoV2SongTitle;
            errdefer allocator.free(song_title);

            const song_subtitle = try getJsonString(root, "_songSubName", allocator) orelse return error.NoV2SongSubtitle;
            errdefer allocator.free(song_subtitle);

            const song_author = try getJsonString(root, "_songAuthorName", allocator) orelse return error.NoV2SongAuthor;
            errdefer allocator.free(song_author);

            const song_filename = try getJsonString(root, "_songFilename", allocator) orelse return error.NoV2SongFilename;
            errdefer allocator.free(song_filename);

            const cover_image_filename = try getJsonString(root, "_coverImageFilename", allocator) orelse return error.NoV2CoverImageFilename;
            errdefer allocator.free(cover_image_filename);

            const song_time_offset = getJsonNumber(f32, root, "_songTimeOffset");
            if (song_time_offset) |_| log.warn("V2 song time offset is present, but deprecated. It will not be handled properly", .{});

            const song_shuffle = getJsonNumber(f32, root, "_shuffle");
            if (song_shuffle) |_| log.warn("V2 song shuffle is present, but deprecated. It will not be handled properly", .{});

            const bpm = getJsonNumber(f32, root, "_beatsPerMinute") orelse return error.NoV2SongBPM;

            const difficulty_sets = getJsonArrayOrEmpty(root, "_difficultyBeatmapSets");
            var difficulty_infos: std.ArrayList(DifficultyInfo) = .{};
            errdefer difficulty_infos.deinit(allocator);

            const author = try getJsonString(root, "_levelAuthorName", allocator) orelse return error.NoV2LevelAuthor;
            defer allocator.free(author);

            for (difficulty_sets) |set| {
                switch (set) {
                    .object => |o| {
                        const difficulties = getJsonArrayOrEmpty(o, "_difficultyBeatmaps");

                        const characteristic_str = try getJsonString(o, "_beatmapCharacteristicName", allocator) orelse return error.NoV2DifficultyCharacteristic;
                        defer allocator.free(characteristic_str);
                        const characteristic = MapCharacteristic.fromString(characteristic_str);

                        for (difficulties) |difficulty| {
                            switch (difficulty) {
                                .object => |d| {
                                    const difficulty_rank_str = try getJsonString(d, "_difficulty", allocator) orelse return error.NoV2DifficultyLabel;
                                    defer allocator.free(difficulty_rank_str);
                                    const difficulty_rank = DifficultyRank.fromString(difficulty_rank_str);

                                    const njs = getJsonNumber(f32, d, "_noteJumpMovementSpeed") orelse return error.NoV2DifficultyNJS;
                                    const nso = getJsonNumber(f32, d, "_noteJumpStartBeatOffset") orelse return error.NoV2DifficultyNSO;

                                    const filename = try getJsonString(d, "_beatmapFilename", allocator) orelse return error.NoV2DifficultyFilename;
                                    errdefer allocator.free(filename);

                                    const author_dupe = try allocator.dupe(u8, author);
                                    errdefer allocator.free(author_dupe);

                                    var synthetic_mappers: std.ArrayList([]u8) = .{};
                                    errdefer synthetic_mappers.deinit(allocator);
                                    try synthetic_mappers.append(allocator, author_dupe);

                                    const author_dupe_2 = try allocator.dupe(u8, author);
                                    errdefer allocator.free(author_dupe_2);

                                    var synthetic_lighters: std.ArrayList([]u8) = .{};
                                    errdefer synthetic_lighters.deinit(allocator);
                                    try synthetic_lighters.append(allocator, author_dupe_2);

                                    try difficulty_infos.append(allocator, .{
                                        .filename = filename,
                                        .characteristic = characteristic,
                                        .rank = difficulty_rank,
                                        .mappers = synthetic_mappers,
                                        .lighters = synthetic_lighters,
                                        .njs = njs,
                                        .nso = nso,
                                    });
                                },
                                else => return error.InvalidV2DifficultyBeatmapType,
                            }

                        }
                    },
                    else => return error.InvalidV2DifficultySetType,
                }
            }

            break :outer .{
                .song_title = song_title,
                .song_subtitle = song_subtitle,
                .song_author = song_author,
                .song_filename = song_filename,
                .cover_image_filename = cover_image_filename,
                .song_time_offset = song_time_offset,
                .bpm = bpm,
                .difficulties = difficulty_infos,
            };
        },
        4 => outer: {
            const song_root = if (root.get("song")) |song| blk: {
                switch (song) {
                    .object => |o| break :blk o,
                    else => return error.InvalidV4SongInfoType,
                }
            } else return error.NoV4SongInfo;

            const song_title = try getJsonString(song_root, "title", allocator) orelse return error.NoV4SongTitle;
            errdefer allocator.free(song_title);

            const song_subtitle = try getJsonString(song_root, "subTitle", allocator) orelse return error.NoV4SongSubtitle;
            errdefer allocator.free(song_subtitle);

            const song_author = try getJsonString(song_root, "author", allocator) orelse return error.NoV4SongAuthor;
            errdefer allocator.free(song_author);

            const audio_root = if (root.get("audio")) |audio| blk: {
                switch (audio) {
                    .object => |a| break :blk a,
                    else => return error.InvalidV4AudioType,
                }
            } else return error.NoV4Audio;

            const song_filename = try getJsonString(audio_root, "songFilename", allocator) orelse return error.NoV4SongFilename;
            errdefer allocator.free(song_filename);

            const bpm = getJsonNumber(f32, audio_root, "bpm") orelse return error.NoV4SongBPM;
            const lufs = getJsonNumber(f32, audio_root, "lufs");
            const duration = getJsonNumber(f32, audio_root, "songDuration");

            const cover_image_filename = try getJsonString(root, "coverImageFilename", allocator) orelse return error.NoV4CoverImageFilename;
            errdefer allocator.free(cover_image_filename);

            const difficulties = getJsonArrayOrEmpty(root, "difficultyBeatmaps");
            var difficulty_infos: std.ArrayList(DifficultyInfo) = .{};
            errdefer difficulty_infos.deinit(allocator);

            for (difficulties) |difficulty| {
                switch (difficulty) {
                    .object => |o| {
                        const characteristic_str = try getJsonString(o, "characteristic", allocator) orelse return error.NoV4DifficultyCharacteristic;
                        defer allocator.free(characteristic_str);
                        const characteristic = MapCharacteristic.fromString(characteristic_str);

                        const difficulty_rank_str = try getJsonString(o, "difficulty", allocator) orelse return error.NoV4DifficultyLabel;
                        defer allocator.free(difficulty_rank_str);
                        const difficulty_rank = DifficultyRank.fromString(difficulty_rank_str);

                        const njs = getJsonNumber(f32, o, "noteJumpMovementSpeed") orelse return error.NoV4DifficultyNJS;
                        const nso = getJsonNumber(f32, o, "noteJumpStartBeatOffset") orelse return error.NoV4DifficultyNSO;

                        const filename = try getJsonString(o, "beatmapDataFilename", allocator) orelse return error.NoV4DifficultyFilename;
                        errdefer allocator.free(filename);

                        const authors = if (o.get("beatmapAuthors")) |authors| blk: {
                            switch (authors) {
                                .object => |a| break :blk a,
                                else => return error.InvalidV4DifficultyAuthorsType,
                            }
                        } else return error.NoV4DifficultyAuthors;
                        const mappers = getJsonArrayOrEmpty(authors, "mappers");
                        const lighters = getJsonArrayOrEmpty(authors, "lighters");

                        var mappers_owned: std.ArrayList([]u8) = .{};
                        errdefer mappers_owned.deinit(allocator);

                        for (mappers) |mapper| {
                            switch (mapper) {
                                .string => |s| {
                                    const owned = try allocator.dupe(u8, s);
                                    errdefer allocator.free(owned);
                                    try mappers_owned.append(allocator, owned);
                                },
                                else => return error.InvalidV4MapperType,
                            }
                        }

                        var lighters_owned: std.ArrayList([]u8) = .{};
                        errdefer lighters_owned.deinit(allocator);

                        for (lighters) |lighter| {
                            switch (lighter) {
                                .string => |s| {
                                    const owned = try allocator.dupe(u8, s);
                                    errdefer allocator.free(owned);
                                    try lighters_owned.append(allocator, owned);
                                },
                                else => return error.InvalidV4LighterType,
                            }
                        }

                        try difficulty_infos.append(allocator, .{
                            .filename = filename,
                            .characteristic = characteristic,
                            .rank = difficulty_rank,
                            .mappers = mappers_owned,
                            .lighters = lighters_owned,
                            .njs = njs,
                            .nso = nso,
                        });
                    },
                    else => return error.InvalidV4DifficultyInfoType,
                }
            }

            break :outer .{
                .song_title = song_title,
                .song_subtitle = song_subtitle,
                .song_author = song_author,
                .song_filename = song_filename,
                .cover_image_filename = cover_image_filename,
                .bpm = bpm,
                .lufs = lufs,
                .duration = duration,
                .difficulties = difficulty_infos,
            };
        },
        else => return error.InvalidMapInfoVersion,
    };
}
