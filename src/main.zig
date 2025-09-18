const std = @import("std");
const rl = @import("raylib");
const rp = @import("replay.zig");
const tweens = @import("tweens.zig");

const FORWARD: rl.Vector3 = .{ .x = 0.0, .y = 0.0, .z = 1.0 };
const UP: rl.Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };
const ONE: rl.Vector3 = .{ .x = 1.0, .y = 1.0, .z = 1.0 };

const GRAPH_SAMPLE_SIZE: usize = 100;
const CUBE_SIZE: f32 = 0.4;

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

const WebReplayInfo = struct {
    replay_url: []u8,
    map_url: []u8,
};

fn fetchReplayInfoFromID(id: u32, gpa: std.mem.Allocator) !WebReplayInfo {
    std.debug.print("Fetching replay info from API\n", .{});

    const url = try std.fmt.allocPrint(gpa, "https://api.beatleader.xyz/score/{}", .{id});
    defer gpa.free(url);

    var client: std.http.Client = .{ .allocator = gpa };
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(gpa);
    defer response_writer.deinit();

    const response = try client.fetch(.{ .method = .GET, .location = .{ .url = url }, .response_writer = &response_writer.writer });

    if (response.status != .ok) {
        return error.HTTP;
    }

    const data = try response_writer.toOwnedSlice();
    defer gpa.free(data);

    const json = try std.json.parseFromSlice(std.json.Value, gpa, data, .{});
    defer json.deinit();

    const replay_url = json.value.object.get("replay").?.string;
    const owned_replay_url = try gpa.alloc(u8, replay_url.len);
    @memcpy(owned_replay_url, replay_url);

    const map_url = json.value.object.get("song").?.object.get("downloadUrl").?.string;
    const owned_map_url = try gpa.alloc(u8, map_url.len);
    @memcpy(owned_map_url, map_url);

    return .{ .replay_url = owned_replay_url, .map_url = owned_map_url };
}

fn downloadReplay(url: []u8, gpa: std.mem.Allocator) !rp.Replay {
    std.debug.print("Downloading replay\n", .{});

    var client: std.http.Client = .{ .allocator = gpa };
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(gpa);
    const response = try client.fetch(.{ .method = .GET, .location = .{ .url = url }, .response_writer = &response_writer.writer });

    if (response.status != .ok) {
        return error.HTTP;
    }

    var reader = std.Io.Reader.fixed(try response_writer.toOwnedSlice());
    defer gpa.free(reader.buffer);

    std.debug.print("Parsing replay\n", .{});

    return rp.parseReplay(&reader, gpa);
}

fn downloadMusic(url: []u8, gpa: std.mem.Allocator) !rl.Music {
    var client: std.http.Client = .{ .allocator = gpa };
    defer client.deinit();

    std.debug.print("Downloading map\n", .{});

    var response_writer = std.Io.Writer.Allocating.init(gpa);
    const response = try client.fetch(.{ .method = .GET, .location = .{ .url = url }, .response_writer = &response_writer.writer });

    if (response.status != .ok) {
        return error.HTTP;
    }

    const zipped = try response_writer.toOwnedSlice();
    defer gpa.free(zipped);

    try std.fs.cwd().writeFile(.{ .sub_path = "the_map.zip", .data = zipped });
    try std.fs.cwd().makePath("map_extracted");

    std.debug.print("Unzipping map\n", .{});
    {
        var directory = try std.fs.cwd().openDir("map_extracted", .{ .iterate = true });
        defer directory.close();

        const song_file = try std.fs.cwd().openFile("the_map.zip", .{});
        defer song_file.close();

        const unzip_buffer = try gpa.alloc(u8, 100000000);
        defer gpa.free(unzip_buffer);

        var reader = song_file.reader(unzip_buffer);
        try std.zip.extract(directory, &reader, .{});
    }

    std.debug.print("Converting music\n", .{});
    const result = try std.process.Child.run(.{ .allocator = gpa, .argv = &.{ "bash", "-c", "ffmpeg -y -i map_extracted/*.egg song.wav" } });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    std.debug.print("Song conversion output: '{s}\n{s}'\n", .{ result.stdout, result.stderr });

    std.debug.print("Loading music\n", .{});
    const sound = rl.loadMusicStream("song.wav");

    try std.fs.cwd().deleteTree("map_extracted");
    try std.fs.cwd().deleteFile("the_map.zip");

    return sound;
}

const TransformInfo = struct { position: rl.Vector3, rotation: rl.Quaternion, rotation_matrix: rl.Matrix, rotation_axis: rl.Vector3, rotation_angle: f64, transform: rl.Matrix, direction: rl.Vector3 };

fn computeAllForms(position: rl.Vector3, rotation: rl.Quaternion) TransformInfo {
    const rotation_matrix = rl.Quaternion.toMatrix(rotation);

    var rotation_axis: rl.Vector3 = undefined;
    var rotation_angle: f32 = 0.0;
    rl.Quaternion.toAxisAngle(rotation, &rotation_axis, &rotation_angle);

    const transform = rl.Matrix.multiply(rotation_matrix, rl.Matrix.translate(position.x, position.y, position.z));

    const direction = FORWARD.transform(rotation_matrix);

    return .{ .position = position, .rotation = rotation, .rotation_matrix = rotation_matrix, .rotation_axis = rotation_axis, .rotation_angle = rotation_angle, .transform = transform, .direction = direction };
}

fn interpolateFrames(a: *const rp.ReplayFrame, b: *const rp.ReplayFrame, time: f64) rp.ReplayFrame {
    const t = rl.math.remap(@floatCast(time), a.time, b.time, 0.0, 1.0);

    return .{
        .time = rl.math.lerp(a.time, b.time, t),
        .fps = b.fps,

        .head_position = rl.Vector3.lerp(a.head_position, b.head_position, t),
        .head_rotation = rl.Quaternion.lerp(a.head_rotation, b.head_rotation, t),

        .left_hand_position = rl.Vector3.lerp(a.left_hand_position, b.left_hand_position, t),
        .left_hand_rotation = rl.Quaternion.lerp(a.left_hand_rotation, b.left_hand_rotation, t),

        .right_hand_position = rl.Vector3.lerp(a.right_hand_position, b.right_hand_position, t),
        .right_hand_rotation = rl.Quaternion.lerp(a.right_hand_rotation, b.right_hand_rotation, t),
    };
}

fn drawLineGraph(x: i32, y: i32, width: i32, height: i32, min_y: f32, max_y: f32, values: []f32, line_color: rl.Color, border_width: f32, border_color: rl.Color, zero_line: bool, gpa: std.mem.Allocator) !void {
    // Draw border
    //rl.drawRectangleLinesEx(.init(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height)), border_width, border_color);
    _ = border_width;
    _ = border_color;

    // Draw zero line
    if (zero_line) {
        const zero: i32 = @intFromFloat(rl.math.remap(0, min_y, max_y, 0, @floatFromInt(height)));
        rl.drawLine(0, zero, width, zero, .gray);
    }

    var points: []rl.Vector2 = try gpa.alloc(rl.Vector2, values.len);
    defer gpa.free(points);

    for (0..values.len, values) |xp, yp| {
        points[xp] = .init(rl.math.remap(@floatFromInt(xp), 0, @floatFromInt(values.len - 1), @floatFromInt(x), @floatFromInt(x + width)), rl.math.remap(yp, min_y, max_y, @floatFromInt(y), @floatFromInt(y + height)));
    }

    // Draw graph
    rl.drawLineStrip(points, line_color);
}

fn drawSaber(position: rl.Vector3, rotation: rl.Quaternion, hilt_mesh: rl.Mesh, hilt_material: rl.Material, blade_mesh: rl.Mesh, blade_material: rl.Material, matrix: rl.Matrix) void {
    const rotation_matrix = rl.Quaternion.toMatrix(rotation);
    const transform = rl.Matrix.multiply(rotation_matrix, rl.Matrix.translate(position.x, position.y, position.z));

    rl.drawMesh(hilt_mesh, hilt_material, transform.multiply(matrix));

    const rotation_matrix_blade = rl.Matrix.rotateX(std.math.pi / 2.0).multiply(rl.Quaternion.toMatrix(rotation));
    const transform_blade = rl.Matrix.multiply(rotation_matrix_blade, rl.Matrix.translate(position.x, position.y, position.z));

    rl.drawMesh(blade_mesh, blade_material, transform_blade.multiply(matrix));
}

fn drawHead(position: rl.Vector3, rotation: rl.Quaternion, mesh: rl.Mesh, material: rl.Material, matrix: rl.Matrix) void {
    const rotation_matrix = rl.Quaternion.toMatrix(rotation);
    const transform = rl.Matrix.scale(1.0, -1.0, 1.0).multiply(rotation_matrix).multiply(rl.Matrix.translate(position.x, position.y, position.z));

    rl.drawMesh(mesh, material, transform.multiply(matrix));
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

pub fn main() !void {
    const FLIP = rl.Matrix.scale(-1.0, 1.0, 1.0);

    // Initialization
    const screen_width = 1600;
    const screen_height = 900;

    rl.initWindow(screen_width, screen_height, "Beat Leader Replay Viewer (Prototype)");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.setTargetFPS(120);

    var camera = rl.Camera{
        .position = .init(2, 2, 2),
        .target = .init(0, 0, 0),
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
    const replay_web_info = try fetchReplayInfoFromID(try inputNumber(), allocator);
    const replay_url = replay_web_info.replay_url;
    const map_url = replay_web_info.map_url;

    std.debug.print("Replay URL: {s}\nMap URL: {s}\n", .{ replay_url, map_url });
    defer allocator.free(replay_url);
    defer allocator.free(map_url);

    var replay = try downloadReplay(replay_url, allocator);
    //var replay = try rp.parseReplayFile("replay.bsor", allocator);
    defer replay.deinit(allocator);

    const music = try downloadMusic(map_url, allocator);
    //const music = try rl.loadMusicStream("song.wav");

    std.debug.print("Parsed replay info:\n", .{});
    replay.dump_info();

    // Keep track of current frame
    var frame_index: usize = 0;

    // Meshes
    const head_mesh = rl.genMeshCube(0.41, 0.23, 0.325);
    const saber_hilt_mesh = rl.genMeshCube(0.05, 0.05, 0.3);
    const saber_blade_mesh = rl.genMeshCylinder(0.015, 1.5, 16);

    // Textures
    const head_texture = try rl.loadTexture("head.png");

    const left_saber_hilt_texture = try rl.loadTexture("left_saber_hilt.png");
    const right_saber_hilt_texture = try rl.loadTexture("right_saber_hilt.png");

    const left_saber_blade_texture = try rl.loadTexture("left_saber.png");
    const right_saber_blade_texture = try rl.loadTexture("right_saber.png");

    // Materials
    var head_material = try rl.loadMaterialDefault();

    var left_saber_hilt_material = try rl.loadMaterialDefault();
    var right_saber_hilt_material = try rl.loadMaterialDefault();

    var left_saber_blade_material = try rl.loadMaterialDefault();
    var right_saber_blade_material = try rl.loadMaterialDefault();

    rl.setMaterialTexture(&head_material, .albedo, head_texture);

    rl.setMaterialTexture(&left_saber_hilt_material, .albedo, left_saber_hilt_texture);
    rl.setMaterialTexture(&right_saber_hilt_material, .albedo, right_saber_hilt_texture);

    rl.setMaterialTexture(&left_saber_blade_material, .albedo, left_saber_blade_texture);
    rl.setMaterialTexture(&right_saber_blade_material, .albedo, right_saber_blade_texture);

    rl.setMaterialTexture(&left_saber_blade_material, .emission, left_saber_blade_texture);
    rl.setMaterialTexture(&right_saber_blade_material, .emission, right_saber_blade_texture);

    rl.playMusicStream(music);

    var music_time: f64 = rl.getMusicTimePlayed(music);
    var replay_time: f64 = music_time;
    var last_music_sync: f64 = rl.getTime();

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
                last_music_sync = rl.getTime();
            }

            replay_time = music_time + rl.getTime() - last_music_sync;

            // Sync frame with replay time
            while (@as(f64, @floatCast(replay.frames.items(.time)[frame_index])) < replay_time) {
                if (frame_index >= replay.frames.len - 1) {
                    break;
                }

                frame_index += 1;
            }

            if (frame_index > 0) {
                frame_index -= 1;
            }

            const interpolated_frame = interpolateFrames(&replay.frames.get(frame_index), &replay.frames.get(frame_index + 1), replay_time);

            // Head
            drawHead(interpolated_frame.head_position, interpolated_frame.head_rotation, head_mesh, head_material, FLIP);

            // Left hand
            drawSaber(interpolated_frame.left_hand_position, interpolated_frame.left_hand_rotation, saber_hilt_mesh, left_saber_hilt_material, saber_blade_mesh, left_saber_blade_material, FLIP);

            // Right hand
            drawSaber(interpolated_frame.right_hand_position, interpolated_frame.right_hand_rotation, saber_hilt_mesh, right_saber_hilt_material, saber_blade_mesh, right_saber_blade_material, FLIP);

            // Draw cut points for note events
            const lookahead: f64 = 2.0;
            const lookbehind: f64 = 1.0;
            for (replay.notes.items(.event_time), replay.notes.items(.spawn_time), replay.notes.items(.line_index), replay.notes.items(.line_layer), replay.notes.items(.cut_info), replay.notes.items(.color)) |event_time, spawn_time, line_index, line_layer, cut_info, color| {
                if (event_time < replay_time - lookbehind) {
                    continue;
                }

                if (event_time > replay_time + lookahead) {
                    break;
                }

                const note_color: rl.Color = switch (color) {
                    .red => .red,
                    else => .blue,
                };
                const line_index_f: f32 = @floatFromInt(2 - line_index);
                const line_layer_f: f32 = @floatFromInt(line_layer);

                const time_distance_offset: f32 = (spawn_time - @as(f32, @floatCast(replay_time))) * replay.jump_distance;
                const note_position: rl.Vector3 = .init(line_index_f / 2.0, replay.height + line_layer_f / 2.0 - 1.0, time_distance_offset);

                if (replay_time < event_time) {
                    rl.drawCubeWiresV(note_position, .init(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE), note_color);
                }

                if (cut_info) |info| {
                    const timed_cut_point = rl.Vector3.init(info.cut_point.x, info.cut_point.y, time_distance_offset);
                    _ = timed_cut_point;

                    // Cut point fly-in animation
                    const total_animation_time = @max(0.0, @min(1.0, 10.0 / info.saber_speed));
                    const animation_start_time = event_time - total_animation_time;
                    const time_to_animation = animation_start_time - replay_time;

                    if (time_to_animation > 0.0) {
                        continue;
                    }

                    var animation_progress = rl.math.remap(@floatCast(replay_time), animation_start_time, event_time, 0.0, 1.0);

                    // Postcut animation
                    if (animation_progress > 1.0) {
                        const animation_end_time = event_time + total_animation_time;
                        animation_progress = rl.math.remap(@floatCast(replay_time), event_time, animation_end_time, 0.0, 1.0);
                        const fade_progress = rl.math.remap(@floatCast(replay_time), event_time, @floatCast(event_time + lookbehind), 0.0, 1.0);

                        const fade_color: rl.Color = .init(255, 255, 255, @as(u8, @intFromFloat(std.math.clamp(255.0 - fade_progress * 255.0, 0.0, 255.0))));
                        const score: i32 = @intFromFloat(std.math.clamp(70.0 * info.before_cut_rating, 0.0, 70.0) + std.math.clamp(30.0 * info.after_cut_rating, 0.0, 30.0) + std.math.clamp((1.0 - std.math.clamp(info.cut_distance_to_center / 0.3, 0.0, 1.0)) * 15.0, 0.0, 15.0));
                        var score_color = getHSVColor(score);
                        score_color.a = fade_color.a;

                        const point = rl.Vector3.lerp(info.cut_point, info.cut_point.add(info.saber_direction.scale(info.saber_speed / 15.0)), animation_progress);
                        const scale = @max(0.0, 1.0 - animation_progress) * CUBE_SIZE;
                        rl.drawCubeV(point.transform(FLIP), .init(scale, scale, scale), score_color);

                        camera.end();
                        defer camera.begin();

                        const screen_space_point = rl.getWorldToScreen(.init(note_position.x, note_position.y, info.cut_point.transform(FLIP).z), camera);

                        if (std.math.isNormal(screen_space_point.x) and std.math.isNormal(screen_space_point.y) and @abs(screen_space_point.x) < @as(f64, @floatFromInt(std.math.maxInt(i32))) and @abs(screen_space_point.y) < @as(f64, @floatFromInt(std.math.maxInt(i32)))) {
                            rl.drawText(rl.textFormat("%03i", .{score}), @as(i32, @intFromFloat(screen_space_point.x)), @as(i32, @intFromFloat(screen_space_point.y)), 25, score_color);
                        }
                    }
                }
            }

            rl.drawGrid(10, 0.5);
        }

        const y_min = 3.0;
        const y_max = 5.0;

        var axis: rl.Vector3 = undefined;
        var angle: f32 = undefined;

        const forward_quaternion = rl.Quaternion.fromVector3ToVector3(.init(0, 0, 0), FORWARD);

        // Left hand motion
        var left_hand_angles: [GRAPH_SAMPLE_SIZE]f32 = .{0.0} ** GRAPH_SAMPLE_SIZE;
        var last_rotation = replay.frames.items(.left_hand_rotation)[0];

        for (1.., replay.frames.items(.left_hand_rotation)[@intCast(@max(1, @as(i64, @intCast(frame_index)) - GRAPH_SAMPLE_SIZE + 1))..frame_index]) |i, rotation| {
            rotation.subtract(forward_quaternion).toAxisAngle(&axis, &angle);
            left_hand_angles[i] = angle;
            last_rotation = rotation;
        }

        try drawLineGraph(0, 0, 400, 200, y_min + 1.0, y_max + 1.0, left_hand_angles[1..], .red, 2, .white, false, allocator);

        // Right hand motion
        var right_hand_angles: [GRAPH_SAMPLE_SIZE]f32 = .{0.0} ** GRAPH_SAMPLE_SIZE;
        last_rotation = replay.frames.items(.right_hand_rotation)[0];

        for (1.., replay.frames.items(.right_hand_rotation)[@intCast(@max(1, @as(i64, @intCast(frame_index)) - GRAPH_SAMPLE_SIZE + 1))..frame_index]) |i, rotation| {
            rotation.subtract(forward_quaternion).toAxisAngle(&axis, &angle);
            right_hand_angles[i] = angle;
            last_rotation = rotation;
        }

        try drawLineGraph(0, 0, 400, 200, y_min, y_max, right_hand_angles[1..], .blue, 2, .white, false, allocator);

        var buffer: [4096]u8 = undefined;
        const text = try std.fmt.bufPrintZ(&buffer, "Player name: {s}\nHeadset: {s}\nMap: {s} ({s})\nMapped by: {s}\nJ/D: {}\nHeight: {}\nFrame: {}\nTotal frames: {}", .{ replay.player_name, replay.hmd, replay.song_name, replay.difficulty_name, replay.mapper_name, replay.jump_distance, replay.height, frame_index, replay.frames.len });
        rl.drawText(text, 0, 210, 24, .white);

        rl.drawFPS(0, 0);
    }
}
