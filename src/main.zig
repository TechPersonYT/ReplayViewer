const std = @import("std");
const rl = @import("raylib");
const rp = @import("replay.zig");
const io = @import("io.zig");
const vs = @import("visual.zig");
const tweens = @import("tweens.zig");
const common = @import("common.zig");

const FORWARD: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 1.0 };
const UP: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };

const GRAPH_SAMPLE_LENGTH: f32 = 2.0;
const GRAPH_WIDTH: i32 = 400;
const GRAPH_HEIGHT: i32 = 200;
const GRAPH_X: i32 = 0;
const GRAPH_Y: i32 = 0;

const CUBE_SIDE_LENGTH: f32 = 0.4;
const CUBE_SIZE: rl.Vector3 = .{ .x = CUBE_SIDE_LENGTH, .y = CUBE_SIDE_LENGTH, .z = CUBE_SIDE_LENGTH };

const CUT_VISUAL_LENGTH: f32 = 0.5;

const TRAIL_DURATION: f32 = 0.25;
const TRAIL_ITERATIONS = 120;

const UNITS_TO_METERS: f32 = 0.6;
const METERS_TO_UNITS: f32 = 1.0 / UNITS_TO_METERS;

const SABER_LENGTH: f32 = 1.0 * METERS_TO_UNITS;

var REPLAY_TO_RAYLIB: ?rl.Matrix = null;

const DOWNLOADED_MAP_FILENAME: []const u8 = "downloaded_map.zip";
const EXTRACTED_MAP_DIRECTORY: []const u8 = "extracted_map";
const CONVERTED_MUSIC_FILENAME: []const u8 = "converted_music.wav";

const SwingTwistDecomposition = struct {
    swing: f32,
    twist: f32,

    // Adapted from https://github.com/TheAllenChou/unity-cj-lib/blob/master/Unity%20CJ%20Lib/Assets/CjLib/Script/Math/QuaternionUtil.cs
    fn fromQuaternion(q: rl.Quaternion) SwingTwistDecomposition {
        // Probably good enough
        const twist_axis = FORWARD;
        const r = rl.Vector3.init(q.x, q.y, q.z);

        var swing: f32 = 0.0;
        var twist: f32 = 0.0;

        // Rotation by 180 degrees
        if (r.lengthSqr() < std.math.floatEps(f32)) {
            const rotated_twist_axis = twist_axis.rotateByQuaternion(q);
            const swing_axis = twist_axis.crossProduct(rotated_twist_axis);

            if (swing_axis.lengthSqr() > std.math.floatEps(f32)) {
                swing = rl.Vector3.angle(twist_axis, rotated_twist_axis);
            }

            // Always twist 180 degrees on singularity
            twist = std.math.pi;
            return .{ .swing = swing, .twist = twist };
        }

        const p = rl.Vector3.project(r, twist_axis);
        const twist_r = rl.Quaternion.init(p.x, p.y, p.z, q.w);

        twist = twist_r.length();
        swing = q.multiply(twist_r.invert()).length();

        return .{ .swing = swing, .twist = twist };
    }
};

fn getHSVColor(score: i64) rl.Color {
    if (score >= 115) {
        return .white;
    } else if (score >= 113) {
        return .init(133, 0, 255, 255);
    } else if (score >= 110) {
        return .init(0, 163, 255, 255);
    } else if (score >= 106) {
        return .init(0, 255, 0, 255);
    } else if (score >= 100) {
        return .init(255, 255, 0, 255);
    } else {
        return .init(255, 0, 56, 255);
    }
}

fn lerpFrameIndexToNext(frame_index: usize, time: f32, frame_times: []f32) f32 {
    const next_frame_index = frame_index + 1;

    return @max(0.0, rl.math.remap(@floatCast(time), frame_times[frame_index], frame_times[next_frame_index], @floatFromInt(frame_index), @floatFromInt(next_frame_index)));
}

fn lerpSlice(slice: anytype, index: f32) std.meta.Elem(@TypeOf(slice)) {
    const Type = std.meta.Elem(@TypeOf(slice));

    const a_index: usize = @intFromFloat(@floor(index));
    const b_index: usize = @intFromFloat(@ceil(index));
    const progress: f32 = 1.0 - (@as(f32, @floatFromInt(b_index)) - index);

    switch (Type) {
        f32, f64 => return rl.math.lerp(slice[a_index], slice[b_index], progress),

        rl.Vector3 => return slice[a_index].lerp(slice[b_index], progress),
        rl.Quaternion => return slice[a_index].slerp(slice[b_index], progress),

        else => {
            //@compileLog("lerpSlice not implemented for " ++ @typeName(Type) ++ ". Will return the first of the two interpolants");
            return slice[a_index];
        },
    }
}

fn lerpSliceMulti(T: type, multi_array_list: std.MultiArrayList(T), index: f32) T {
    const Container = @TypeOf(multi_array_list);
    const slice = multi_array_list.slice();

    var result: T = undefined;

    inline for (std.meta.fields(T), 0..) |field, i| {
        @field(result, field.name) = lerpSlice(slice.items(@as(Container.Field, @enumFromInt(i))), index);
    }

    return result;
}

fn drawLineGraph(x: i32, y: i32, width: i32, height: i32, min_y: f32, max_y: f32, mid_y: f32, values: []f32, line_color: rl.Color, border_width: f32, border_color: rl.Color, zero_line: bool, allocator: std.mem.Allocator) !void {
    // Draw border
    //rl.drawRectangleLinesEx(.init(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height)), border_width, border_color);
    _ = border_width;
    _ = border_color;

    // Draw zero line
    if (zero_line) {
        const zero: i32 = @intFromFloat(rl.math.remap(mid_y, min_y, max_y, 0, @floatFromInt(height)));
        rl.drawLine(0, zero, width, zero, .gray);
    }

    var points: []rl.Vector2 = try allocator.alloc(rl.Vector2, values.len);
    defer allocator.free(points);

    for (0..values.len, values) |xp, yp| {
        points[xp] = .init(rl.math.remap(@floatFromInt(xp), 0, @floatFromInt(values.len - 1), @floatFromInt(x), @floatFromInt(x + width)), rl.math.remap(yp, min_y, max_y, @floatFromInt(y), @floatFromInt(y + height)));
    }

    // Draw graph
    rl.drawLineStrip(points, line_color);
}

fn drawScoreDotGraph(x: i32, y: i32, width: i32, height: i32, scores: []f32, min_y: f32, max_y: f32, values: []f32, radius: f32, border_width: f32, border_color: rl.Color, zero_line: bool) void {
    // Draw border
    //rl.drawRectangleLinesEx(.init(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height)), border_width, border_color);
    _ = border_width;
    _ = border_color;

    const zero: i32 = @intFromFloat(rl.math.remap(0, 0, 115, 0, @floatFromInt(height)));

    // Draw zero line
    if (zero_line) {
        rl.drawLine(0, zero, width, zero, .gray);
    }

    for (0..values.len, scores, values) |xp, yp, yp2| {
        if (yp < 0.0) {
            continue;
        }

        const h = rl.math.remap(yp2, min_y, max_y, @floatFromInt(y), @floatFromInt(y + height));
        const v = rl.Vector2.init(rl.math.remap(@floatFromInt(xp), 0, @floatFromInt(scores.len - 1), @floatFromInt(x), @floatFromInt(x + width)), h);
        rl.drawCircleV(v, radius + 1, .white);
        rl.drawCircleV(v, radius, getHSVColor(@intFromFloat(@abs(yp))));
    }
}

fn drawSaber(position: rl.Vector3, rotation: rl.Quaternion, hilt_mesh: *const rl.Mesh, hilt_material: *const rl.Material, blade_mesh: *const rl.Mesh, blade_material: *const rl.Material) void {
    const rotation_matrix = rl.Quaternion.toMatrix(rotation);
    const transform = rl.Matrix.multiply(rotation_matrix, rl.Matrix.translate(position.x, position.y, position.z));

    rl.drawMesh(hilt_mesh.*, hilt_material.*, toRaylib(transform));

    const rotation_matrix_blade = rl.Matrix.rotateX(std.math.pi / 2.0).multiply(rl.Quaternion.toMatrix(rotation));
    const blade_transform = rl.Matrix.multiply(rotation_matrix_blade, rl.Matrix.translate(position.x, position.y, position.z));

    rl.drawMesh(blade_mesh.*, blade_material.*, toRaylib(blade_transform));
}

fn drawHead(position: rl.Vector3, rotation: rl.Quaternion, mesh: *const rl.Mesh, material: *const rl.Material) void {
    const rotation_matrix = rl.Quaternion.toMatrix(rotation);
    const transform = rl.Matrix.scale(1.0, -1.0, 1.0).multiply(rotation_matrix).multiply(rl.Matrix.translate(position.x, position.y, position.z));

    rl.drawMesh(mesh.*, material.*, toRaylib(transform));
}

fn inputNumber() !u32 {
    var stdin_buffer: [1024]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&stdin_buffer);

    var line_buffer: [1024]u8 = undefined;
    var w: std.io.Writer = .fixed(&line_buffer);

    // Read an input until "\n" or end of file, and write it to the buffer
    const line_length = try stdin.interface.streamDelimiterLimit(&w, '\n', .unlimited);

    const input_line = line_buffer[0..line_length];

    return try std.fmt.parseInt(u32, input_line, 10);
}

fn toRaylib(v: anytype) @TypeOf(v) {
    const Type = @TypeOf(v);

    if (REPLAY_TO_RAYLIB) |matrix| {
        switch (Type) {
            rl.Matrix => return v.multiply(matrix),
            rl.Vector3 => return v.transform(matrix),
            else => unreachable,
        }
    } else {
        return v;
    }
}

fn getNoteColor(color: common.NoteColor) rl.Color {
    return switch (color) {
        .red => .red,
        .blue => .blue,

        else => .magenta,
    };
}

fn computeTimedNoteZ(replay_time: f32, spawn_time: f32, jump_distance: f32, jump_speed: f32) f32 {
    const elapsed = replay_time - spawn_time;
    _ = jump_distance;

    return (-elapsed * jump_speed) * METERS_TO_UNITS;
}

fn withAlpha(color: rl.Color, alpha: u8) rl.Color {
    return .init(color.r, color.g, color.b, alpha);
}

fn quaternionConjugate(q: rl.Quaternion) rl.Quaternion {
    return .{ .x = -q.x, .y = -q.y, .z = -q.z, .w = q.w };
}

fn computeCutScore(info: rp.CutInfo) i32 {
    return @intFromFloat(std.math.clamp(70.0 * info.before_cut_rating, 0.0, 70.0) + std.math.clamp(30.0 * info.after_cut_rating, 0.0, 30.0) + std.math.clamp((1.0 - std.math.clamp(info.cut_distance_to_center / 0.3, 0.0, 1.0)) * 15.0, 0.0, 15.0));
}

fn drawSaberTrail(positions: []rl.Vector3, rotations: []rl.Quaternion, time: f32, times: []f32, trail_color: rl.Color) void {
    const iterations = TRAIL_ITERATIONS;
    const lookbehind = TRAIL_DURATION / @as(f32, @floatFromInt(iterations));

    var last_frame = lerpFrameIndexToNext(timeToIndex(time, times), time, times);
    var last_position = lerpSlice(positions, last_frame);
    var last_rotation = lerpSlice(rotations, last_frame);

    for (1..iterations) |i| {
        const new_time = time - @as(f32, @floatFromInt(i)) * lookbehind;
        const frame = lerpFrameIndexToNext(timeToIndex(new_time, times), new_time, times);
        const position = lerpSlice(positions, frame);
        const rotation = lerpSlice(rotations, frame);

        rl.drawLine3D(toRaylib(calculateSaberTipPosition(last_position, last_rotation)), toRaylib(calculateSaberTipPosition(position, rotation)), withAlpha(trail_color, @intFromFloat(@as(f32, @floatFromInt(iterations - i + 1)) / @as(f32, @floatFromInt(iterations)) * 255)));

        last_frame = frame;
        last_position = position;
        last_rotation = rotation;
    }
}

fn calculateSaberTipPosition(hilt_position: rl.Vector3, hilt_rotation: rl.Quaternion) rl.Vector3 {
    return hilt_position.add(FORWARD.scale(SABER_LENGTH).rotateByQuaternion(hilt_rotation));
}

fn orderF32(a: f32, b: f32) std.math.Order {
    return std.math.order(a, b);
}

fn timeToIndex(time: f32, times: []f32) usize {
    return std.math.sub(usize, std.sort.lowerBound(f32, times, time, orderF32), 1) catch 0;
}

fn timeRangeToSliceRange(start_time: f32, end_time: f32, times: []f32) struct { ?usize, ?usize } {
    const lower: usize = timeToIndex(start_time, times);
    if (lower == times.len) return .{ null, null };

    var upper: ?usize = timeToIndex(end_time, times[lower..]);
    if (lower + upper.? == times.len) upper = null;

    return .{ lower, upper };
}

fn timeSliceMulti(start_time: f32, end_time: f32, multi_slice: anytype, time_field: anytype) @TypeOf(multi_slice) {
    const first, const len = timeRangeToSliceRange(start_time, end_time, multi_slice.items(time_field));

    if (first) |f| {
        if (len) |l| return multi_slice.subslice(f, l)
        else return multi_slice.subslice(f, multi_slice.len - f);
    } else {
        return multi_slice.subslice(0, 0);
    }
}

fn drawNote(note_mesh: *const rl.Mesh, red_note_material: *const rl.Material, red_note_dot_material: *const rl.Material, blue_note_material: *const rl.Material, blue_note_dot_material: *const rl.Material, note_color: common.NoteColor, note_transform: rl.Matrix, note_direction: common.CutDirection) void {
    if (note_direction != .dot) {
        switch (note_color) {
            .red => rl.drawMesh(note_mesh.*, red_note_material.*, note_transform),
            .blue => rl.drawMesh(note_mesh.*, blue_note_material.*, note_transform),

            else => {},
        }
    } else {
        switch (note_color) {
            .red => rl.drawMesh(note_mesh.*, red_note_dot_material.*, note_transform),
            .blue => rl.drawMesh(note_mesh.*, blue_note_dot_material.*, note_transform),

            else => {},
        }
    }
}

fn computeSwingTwistDecomps(swing_twists: *std.MultiArrayList(SwingTwistDecomposition), rotations: []rl.Quaternion, allocator: std.mem.Allocator) !void {
    for (rotations) |rotation| {
        try swing_twists.append(allocator, SwingTwistDecomposition.fromQuaternion(rotation));
    }
}

pub fn main() !void {
    REPLAY_TO_RAYLIB = rl.Matrix.scale(-1.0, 1.0, 1.0);

    // Initialization
    const screen_width = 1600;
    const screen_height = 900;

    rl.initWindow(screen_width, screen_height, "Beat Leader Replay Viewer (Prototype)");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setTargetFPS(120);

    var camera = rl.Camera{
        .position = .init(-1, 2, -3.5),
        .target = .init(0, 1, 0),
        .up = .init(0, 1, 0),
        .fovy = 70,
        .projection = .perspective,
    };

    // Memory
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    var gpa_result: std.heap.Check = undefined;
    const allocator = gpa.allocator();
    defer gpa_result = gpa.deinit();

    // Get replay
    _ = try std.fs.File.stdout().write("Enter replay ID: ");
    const replay_web_info = try io.fetchReplayInfoFromID(try inputNumber(), allocator);
    const replay_url = replay_web_info.replay_url;
    const map_url = replay_web_info.map_url;
    const map_filename = replay_web_info.map_filename;

    defer allocator.free(replay_url);
    defer allocator.free(map_url);
    defer allocator.free(map_filename);

    var replay = try io.downloadReplay(replay_url, allocator);
    //var replay = try rp.parseReplayFile("replay.bsor", allocator);
    defer replay.deinit(allocator);

    var map, var map_info, const music = try io.downloadMapAndMusic(map_url, DOWNLOADED_MAP_FILENAME, EXTRACTED_MAP_DIRECTORY, map_filename, CONVERTED_MUSIC_FILENAME, allocator);
    defer map.deinit(allocator);
    defer map_info.deinit(allocator);
    //const music = try rl.loadMusicStream("song.wav");

    replay.dump_info();

    // Keep track of current frame
    var frame_index: usize = 0;

    // Meshes
    const head_mesh = rl.genMeshCube(0.41, 0.23, 0.325);
    const saber_hilt_mesh = rl.genMeshCube(0.05, 0.05, 0.3);
    const saber_blade_mesh = rl.genMeshCylinder(0.015, SABER_LENGTH, 16);
    const note_mesh = rl.genMeshCube(CUBE_SIDE_LENGTH, CUBE_SIDE_LENGTH, CUBE_SIDE_LENGTH);

    // Textures
    const head_texture = try rl.loadTexture("assets/head.png");

    const left_saber_hilt_texture = try rl.loadTexture("assets/left_saber_hilt.png");
    const right_saber_hilt_texture = try rl.loadTexture("assets/right_saber_hilt.png");

    const left_saber_blade_texture = try rl.loadTexture("assets/left_saber.png");
    const right_saber_blade_texture = try rl.loadTexture("assets/right_saber.png");

    const red_note_texture = try rl.loadTexture("assets/red_note.png");
    const blue_note_texture = try rl.loadTexture("assets/blue_note.png");

    const red_note_dot_texture = try rl.loadTexture("assets/red_note_dot.png");
    const blue_note_dot_texture = try rl.loadTexture("assets/blue_note_dot.png");

    rl.setTextureWrap(red_note_texture, .clamp);
    rl.setTextureWrap(blue_note_texture, .clamp);

    rl.setTextureWrap(red_note_dot_texture, .clamp);
    rl.setTextureWrap(blue_note_dot_texture, .clamp);

    // Materials
    var head_material = try rl.loadMaterialDefault();

    var left_saber_hilt_material = try rl.loadMaterialDefault();
    var right_saber_hilt_material = try rl.loadMaterialDefault();

    var left_saber_blade_material = try rl.loadMaterialDefault();
    var right_saber_blade_material = try rl.loadMaterialDefault();

    var red_note_material = try rl.loadMaterialDefault();
    var blue_note_material = try rl.loadMaterialDefault();

    var red_note_dot_material = try rl.loadMaterialDefault();
    var blue_note_dot_material = try rl.loadMaterialDefault();

    rl.setMaterialTexture(&head_material, .albedo, head_texture);

    rl.setMaterialTexture(&left_saber_hilt_material, .albedo, left_saber_hilt_texture);
    rl.setMaterialTexture(&right_saber_hilt_material, .albedo, right_saber_hilt_texture);

    rl.setMaterialTexture(&left_saber_blade_material, .albedo, left_saber_blade_texture);
    rl.setMaterialTexture(&right_saber_blade_material, .albedo, right_saber_blade_texture);

    rl.setMaterialTexture(&left_saber_blade_material, .emission, left_saber_blade_texture);
    rl.setMaterialTexture(&right_saber_blade_material, .emission, right_saber_blade_texture);

    rl.setMaterialTexture(&red_note_material, .albedo, red_note_texture);
    rl.setMaterialTexture(&blue_note_material, .albedo, blue_note_texture);

    rl.setMaterialTexture(&red_note_dot_material, .albedo, red_note_dot_texture);
    rl.setMaterialTexture(&blue_note_dot_material, .albedo, blue_note_dot_texture);

    rl.playMusicStream(music);

    var music_time: f32 = rl.getMusicTimePlayed(music);
    var replay_time: f32 = @floatCast(music_time);
    var last_music_sync: f32 = @floatCast(rl.getTime());

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        rl.updateMusicStream(music);

        if (!rl.isMusicStreamPlaying(music)) {
            break;
        }

        // Update
        if (rl.isMouseButtonPressed(.right)) {
            rl.disableCursor();
        }

        if (rl.isMouseButtonReleased(.right)) {
            rl.enableCursor();
        }

        if (rl.isMouseButtonDown(.right)) {
            camera.update(.free);
        }

        const replay_frame_slices = replay.frames.slice();
        const replay_note_slices = replay.notes.slice();

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        {
            // Camera
            camera.begin();
            defer camera.end();

            // Sync with music every second
            if (rl.getTime() - last_music_sync > 1.0) {
                music_time = rl.getMusicTimePlayed(music);
                last_music_sync = @floatCast(rl.getTime());
            }

            replay_time = music_time + @as(f32, @floatCast(rl.getTime())) - last_music_sync;

            // Sync frame with replay time
            // FIXME: If we didn't have a frame for this time, other events we did have might not be interpolated correctly
            frame_index = timeToIndex(replay_time, replay.frames.items(.time));

            if (frame_index + 2 >= replay.frames.len) {
                break;
            }

            const interpolated_frame_index: f32 = lerpFrameIndexToNext(frame_index, replay_time, replay.frames.items(.time));
            const interpolated_frame = lerpSliceMulti(rp.Frame, replay.frames, interpolated_frame_index);

            // Head
            drawHead(interpolated_frame.head_position, interpolated_frame.head_rotation, &head_mesh, &head_material);

            // Left hand
            drawSaber(interpolated_frame.left_hand_position, interpolated_frame.left_hand_rotation, &saber_hilt_mesh, &left_saber_hilt_material, &saber_blade_mesh, &left_saber_blade_material);
            drawSaberTrail(replay_frame_slices.items(.left_hand_position), replay_frame_slices.items(.left_hand_rotation), replay_time, replay_frame_slices.items(.time), .red);

            // Right hand
            drawSaber(interpolated_frame.right_hand_position, interpolated_frame.right_hand_rotation, &saber_hilt_mesh, &right_saber_hilt_material, &saber_blade_mesh, &right_saber_blade_material);
            drawSaberTrail(replay_frame_slices.items(.right_hand_position), replay_frame_slices.items(.right_hand_rotation), replay_time, replay_frame_slices.items(.time), .blue);

            // Note events
            const lookahead = 2.0;
            const lookbehind = 1.0;
            const view_start_time: f32 = replay_time - lookbehind;
            const view_end_time: f32 = replay_time + lookahead;
            const actual_height = if (replay.height <= 0.05) replay.heights.items(.height)[0] else replay.height;
            _ = actual_height;

            const replay_notes = timeSliceMulti(view_start_time, view_end_time, replay_note_slices, .event_time);
            //const replay_bombs = timeSliceMulti(view_start_time, view_end_time, replay_bomb_slices);

            const jump_speed = map_info.jump_speeds.items[map_info.jump_speeds.items.len - 1];

            for (replay_notes.items(.placement),
                 replay_notes.items(.event_time),
                 replay_notes.items(.cut_direction),
                 replay_notes.items(.cut_info),
                 replay_notes.items(.color)) |placement,
                                              event_time,
                                              note_direction,
                                              cut_info,
                                              note_color| {
                const z_time = computeTimedNoteZ(replay_time, placement.time, replay.jump_distance, jump_speed);
                _ = z_time;

                const jump_info = vs.getNoteJumpInfo2(jump_speed, replay.jump_distance);
                const note_transform = vs.getTimedNotePose(placement, note_direction, replay_time, jump_info, false);
                const note_position = rl.Vector3.transform(.init(0.0, 0.0, 0.0), note_transform);
                //const note_position = computeNotePosition(placement.line_index, placement.line_layer, z_time, actual_height);

                if (replay_time < event_time) {
                    drawNote(&note_mesh, &red_note_material, &red_note_dot_material, &blue_note_material, &blue_note_dot_material, note_color, note_transform, note_direction);
                }

                if (cut_info) |info| {
                    const frozen_note_position: rl.Vector3 = .init(note_position.x, note_position.y, computeTimedNoteZ(event_time, placement.time, replay.jump_distance, jump_speed));

                    // Postcut animation
                    if (replay_time > event_time) {
                        const animation_progress = rl.math.remap(replay_time, event_time, view_end_time, 0.0, 1.0);

                        const fade_color: rl.Color = .init(175, 175, 175, @as(u8, @intFromFloat(std.math.clamp(255.0 - animation_progress * 255.0, 0.0, 255.0))));
                        const score = computeCutScore(info);
                        const score_color = withAlpha(getHSVColor(score), fade_color.a);

                        rl.drawLine3D(frozen_note_position, toRaylib(info.cut_point), withAlpha(.red, fade_color.a));
                        rl.drawCubeWiresV(frozen_note_position, CUBE_SIZE, withAlpha(getNoteColor(note_color), fade_color.a));

                        const cut_direction = rl.Vector3.init(info.cut_normal.x, info.cut_normal.y, 0.0).perpendicular().negate().normalize();
                        rl.drawLine3D(toRaylib(info.cut_point), toRaylib(info.cut_point.add(cut_direction.scale(@min(CUT_VISUAL_LENGTH, (replay_time - event_time) * info.saber_speed)))), fade_color);

                        const flyaway_vector = cut_direction.scale(info.saber_speed / 2.0);
                        const point = rl.Vector3.lerp(info.cut_point, info.cut_point.add(flyaway_vector), animation_progress);
                        const scale = @max(0.0, 1.0 - animation_progress);
                        rl.drawSphere(toRaylib(point), 0.1 * scale, score_color);

                        camera.end();
                        defer camera.begin();

                        const screen_space_point = rl.getWorldToScreen(frozen_note_position, camera);

                        if (std.math.isNormal(screen_space_point.x) and std.math.isNormal(screen_space_point.y) and @abs(screen_space_point.x) < @as(f64, @floatFromInt(std.math.maxInt(i32))) and @abs(screen_space_point.y) < @as(f64, @floatFromInt(std.math.maxInt(i32)))) {
                            rl.drawText(rl.textFormat("%03i", .{score}), @as(i32, @intFromFloat(screen_space_point.x)), @as(i32, @intFromFloat(screen_space_point.y)), 25, score_color);
                        }
                    }
                }
            }

            rl.drawGrid(10, 0.5);
        }

        const sample_start_time = replay_time - GRAPH_SAMPLE_LENGTH;
        const sample_end_time = replay_time;

        //const sampled_frames = timeSliceMulti(sample_start_time, sample_end_time);
        const sampled_notes = timeSliceMulti(sample_start_time, sample_end_time, replay_note_slices, .event_time);

        // Cut scores
        var cut_scores_left: std.ArrayList(f32) = .{};
        defer cut_scores_left.deinit(allocator);

        var cut_scores_right: std.ArrayList(f32) = .{};
        defer cut_scores_right.deinit(allocator);

        var score_times: std.ArrayList(f32) = .{};
        defer score_times.deinit(allocator);

        for (sampled_notes.items(.event_time),
             sampled_notes.items(.cut_info),
             sampled_notes.items(.color)) |time, cut_info, color| {
            if (cut_info) |cut| {
                switch (color) {
                    .red => try cut_scores_left.append(allocator, @floatFromInt(computeCutScore(cut))),
                    .blue => try cut_scores_right.append(allocator, @floatFromInt(computeCutScore(cut))),

                    else => {},
                }

                try score_times.append(allocator, time);
            }
        }

        //drawScoreDotGraph(GRAPH_X, GRAPH_Y, GRAPH_WIDTH, GRAPH_HEIGHT, &cut_scores_left, y_min, y_max, &left_hand_angles, 4, 2, .white, false);
        //drawScoreDotGraph(GRAPH_X, GRAPH_Y, GRAPH_WIDTH, GRAPH_HEIGHT, &cut_scores_right, y_min, y_max, &right_hand_angles, 4, 2, .white, false);

        var buffer: [4096]u8 = undefined;
        const text = try std.fmt.bufPrintZ(&buffer, "Player name: {s}\nHeadset: {s}\nMap: {s} ({s})\nMapped by: {s}\nJ/D: {}\nHeight: {}\nFrame: {}\nTotal frames: {}", .{ replay.player_name, replay.hmd, replay.song_name, replay.difficulty_name, replay.mapper_name, replay.jump_distance, replay.height, frame_index, replay.frames.len });
        rl.drawText(text, 0, 210, 24, .white);

        rl.drawFPS(0, 0);
    }
}
