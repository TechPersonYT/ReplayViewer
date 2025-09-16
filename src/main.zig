const std = @import("std");
const rl = @import("raylib");
const rp = @import("replay.zig");

const FORWARD: rl.Vector3 = .{.x = 0.0, .y = 0.0, .z = 1.0};
const ONE: rl.Vector3 = .{.x = 1.0, .y = 1.0, .z = 1.0};

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

fn easeOutQuart(x: f32) f32 {
    return 1.0 - std.math.pow(f32, 1.0 - x, 4.0);
}

fn fetchReplayInfoFromID(id: u32, gpa: std.mem.Allocator) !WebReplayInfo {
    std.debug.print("Fetching replay info from API\n", .{});

    const url = try std.fmt.allocPrint(gpa, "https://api.beatleader.xyz/score/{}", .{id});
    defer gpa.free(url);

    var client: std.http.Client = .{.allocator = gpa};
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(gpa);
    defer response_writer.deinit();

    const response = try client.fetch(.{.method = .GET, .location = .{.url = url}, .response_writer = &response_writer.writer});

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

    return .{.replay_url = owned_replay_url, .map_url = owned_map_url};
}

fn downloadReplay(url: []u8, gpa: std.mem.Allocator) !rp.Replay {
    std.debug.print("Downloading replay\n", .{});

    var client: std.http.Client = .{.allocator = gpa};
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(gpa);
    const response = try client.fetch(.{.method = .GET, .location = .{.url = url}, .response_writer = &response_writer.writer});

    if (response.status != .ok) {
        return error.HTTP;
    }

    var reader = std.Io.Reader.fixed(try response_writer.toOwnedSlice());
    defer gpa.free(reader.buffer);

    std.debug.print("Parsing replay\n", .{});

    return rp.parseReplay(&reader, gpa);
}

fn downloadMusic(url: []u8, gpa: std.mem.Allocator) !rl.Music {
    var client: std.http.Client = .{.allocator = gpa};
    defer client.deinit();

    std.debug.print("Downloading map\n", .{});

    var response_writer = std.Io.Writer.Allocating.init(gpa);
    const response = try client.fetch(.{.method = .GET, .location = .{.url = url}, .response_writer = &response_writer.writer});

    if (response.status != .ok) {
        return error.HTTP;
    }

    const zipped = try response_writer.toOwnedSlice();
    defer gpa.free(zipped);

    try std.fs.cwd().writeFile(.{.sub_path = "the_map.zip", .data = zipped});
    try std.fs.cwd().makePath("map_extracted");

    std.debug.print("Unzipping map\n", .{});
    {
        var directory = try std.fs.cwd().openDir("map_extracted", .{.iterate = true});
        defer directory.close();

        const song_file = try std.fs.cwd().openFile("the_map.zip", .{});
        defer song_file.close();

        const unzip_buffer = try gpa.alloc(u8, 100000000);
        defer gpa.free(unzip_buffer);

        var reader = song_file.reader(unzip_buffer);
        try std.zip.extract(directory, &reader, .{});
    }

    std.debug.print("Converting music\n", .{});
    const result = try std.process.Child.run(.{.allocator = gpa, .argv = &.{"bash", "-c", "ffmpeg -y -i map_extracted/*.egg song.wav"}});
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    std.debug.print("Song conversion output: '{s}\n{s}'\n", .{result.stdout, result.stderr});

    std.debug.print("Loading music\n", .{});
    const sound = rl.loadMusicStream("song.wav");

    try std.fs.cwd().deleteTree("map_extracted");
    try std.fs.cwd().deleteFile("the_map.zip");

    return sound;
}

const TransformInfo = struct {
    position: rl.Vector3,
    rotation: rl.Quaternion,
    rotation_matrix: rl.Matrix,
    rotation_axis: rl.Vector3,
    rotation_angle: f64,
    transform: rl.Matrix,
    direction: rl.Vector3
};

fn computeAllForms(position: rl.Vector3, rotation: rl.Quaternion) TransformInfo {
    const rotation_matrix = rl.Quaternion.toMatrix(rotation);

    var rotation_axis: rl.Vector3 = undefined;
    var rotation_angle: f32 = 0.0;
    rl.Quaternion.toAxisAngle(rotation, &rotation_axis, &rotation_angle);

    const transform = rl.Matrix.multiply(rotation_matrix, rl.Matrix.translate(position.x, position.y, position.z));

    const direction = FORWARD.transform(rotation_matrix);

    return .{.position = position, .rotation = rotation, .rotation_matrix = rotation_matrix, .rotation_axis = rotation_axis, .rotation_angle = rotation_angle, .transform = transform, .direction = direction};
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

pub fn main() !void {
    // Initialization
    const screen_width = 1280;
    const screen_height = 720;

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
    const replay_web_info = try fetchReplayInfoFromID(14529303, allocator);
    const replay_url = replay_web_info.replay_url;
    const map_url = replay_web_info.map_url;

    std.debug.print("Replay URL: {s}\nMap URL: {s}\n", .{replay_url, map_url});
    defer allocator.free(replay_url);
    defer allocator.free(map_url);

    var replay = try downloadReplay(replay_url, allocator);
    defer replay.deinit(allocator);

    const music = try downloadMusic(map_url, allocator);

    std.debug.print("Parsed replay info:\n", .{});
    replay.dump_info();

    // Keep track of current frame
    var frame_index: usize = 0;

    // Meshes
    const head_mesh = rl.genMeshCube(0.41, 0.23, 0.325);
    const saber_hilt_mesh = rl.genMeshCube(0.05, 0.05, 0.3);

    // Textures
    const head_texture = try rl.loadTexture("head.png");
    const left_saber_texture = try rl.loadTexture("left_saber.png");
    const right_saber_texture = try rl.loadTexture("right_saber.png");

    // Materials
    var head_material = try rl.loadMaterialDefault();
    var left_saber_material = try rl.loadMaterialDefault();
    var right_saber_material = try rl.loadMaterialDefault();

    // TODO: emission, roughness
    rl.setMaterialTexture(&head_material, .albedo, head_texture);
    rl.setMaterialTexture(&left_saber_material, .albedo, left_saber_texture);
    rl.setMaterialTexture(&right_saber_material, .albedo, right_saber_texture);

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
            var transform_info = computeAllForms(interpolated_frame.head_position, interpolated_frame.head_rotation);
            rl.drawMesh(head_mesh, head_material, transform_info.transform);

            // Left hand
            transform_info = computeAllForms(interpolated_frame.left_hand_position, interpolated_frame.left_hand_rotation);
            rl.drawMesh(saber_hilt_mesh, left_saber_material, transform_info.transform);
            rl.drawLine3D(transform_info.position, transform_info.position.add(transform_info.direction.scale(2)), .red);

            // Right hand
            transform_info = computeAllForms(interpolated_frame.right_hand_position, interpolated_frame.right_hand_rotation);
            rl.drawMesh(saber_hilt_mesh, right_saber_material, transform_info.transform);
            rl.drawLine3D(transform_info.position, transform_info.position.add(transform_info.direction.scale(2)), .blue);

            // Draw cut points for note events
            const lookahead: f64 = 2.0;
            const lookbehind: f64 = 1.0;
            for (replay.notes.items(.event_time), replay.notes.items(.spawn_time), replay.notes.items(.cut_info), replay.notes.items(.color)) |event_time, spawn_time, cut_info, color| {
                if (event_time < replay_time - lookbehind) {
                    continue;
                }

                if (event_time > replay_time + lookahead) {
                    break;
                }

                _ = spawn_time;

                if (cut_info) |info| {
                    const sphere_color: rl.Color = switch (color) {.red => .red, .blue => .blue};

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

                        const fade_color: rl.Color = .init(255, 255, 255, @as(u8, @intFromFloat(std.math.clamp(255.0 - animation_progress * 255.0, 0.0, 255.0))));
                        const score: i32 = @intFromFloat(std.math.clamp(70.0 * info.before_cut_rating, 0.0, 70.0) + std.math.clamp(30.0 * info.after_cut_rating, 0.0, 30.0) + std.math.clamp((1.0 - std.math.clamp(info.cut_distance_to_center / 0.3, 0.0, 1.0)) * 15.0, 0.0, 15.0));
                        var score_color = getHSVColor(score);
                        score_color.a = fade_color.a;

                        const point = rl.Vector3.lerp(info.cut_point, info.cut_point.add(info.saber_direction.scale(info.saber_speed / 15.0)), animation_progress);
                        rl.drawSphere(point, (1.0 - animation_progress) * 0.08, fade_color);

                        camera.end();
                        defer camera.begin();

                        const screen_space_point = rl.getWorldToScreen(point, camera);

                        rl.drawText(rl.textFormat("%03i", .{score}), @as(i32, @intFromFloat(screen_space_point.x)), @as(i32, @intFromFloat(screen_space_point.y)), 25, score_color);
                    } else {
                        const point = rl.Vector3.lerp(info.cut_point.subtract(info.cut_normal), info.cut_point, animation_progress);
                        rl.drawSphere(point, @min(0.08, animation_progress * 0.08), sphere_color);
                    }
                }
            }

            rl.drawGrid(10, 0.5);
        }

        rl.drawFPS(0, 0);
    }
}

