const std = @import("std");
const rl = @import("raylib");
const rp = @import("replay.zig");

const FORWARD: rl.Vector3 = .{.x = 0.0, .y = 0.0, .z = 1.0};

const WebReplayInfo = struct {
    replay_url: []u8,
    map_url: []u8,
};

fn fetchReplayInfoFromID(id: u32, gpa: std.mem.Allocator) !WebReplayInfo {
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
    var client: std.http.Client = .{.allocator = gpa};
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(gpa);
    const response = try client.fetch(.{.method = .GET, .location = .{.url = url}, .response_writer = &response_writer.writer});

    if (response.status != .ok) {
        return error.HTTP;
    }

    var reader = std.Io.Reader.fixed(try response_writer.toOwnedSlice());
    defer gpa.free(reader.buffer);

    return rp.parseReplay(&reader, gpa);
}

fn downloadAudio(url: []u8, gpa: std.mem.Allocator) !rl.Sound {
    var client: std.http.Client = .{.allocator = gpa};
    defer client.deinit();

    var response_writer = std.Io.Writer.Allocating.init(gpa);
    const response = try client.fetch(.{.method = .GET, .location = .{.url = url}, .response_writer = &response_writer.writer});

    if (response.status != .ok) {
        return error.HTTP;
    }

    const zipped = try response_writer.toOwnedSlice();
    defer gpa.free(zipped);

    try std.fs.cwd().writeFile(.{.sub_path = "the_map.zip", .data = zipped});
    try std.fs.cwd().makePath("map_extracted");

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

    const sound = rl.loadSound("map_extracted/song.egg");

    try std.fs.cwd().deleteTree("map_extracted");
    try std.fs.cwd().deleteFile("the_map.zip");

    return sound;
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
    //var replay = try rp.parseReplayFile("/home/techperson/example_replay.bsor", allocator);
    const replay_web_info = try fetchReplayInfoFromID(26463918, allocator);
    const replay_url = replay_web_info.replay_url;
    const map_url = replay_web_info.map_url;

    std.debug.print("Replay URL: {s}\nMap URL: {s}\n", .{replay_url, map_url});
    defer allocator.free(replay_url);
    defer allocator.free(map_url);

    var replay = try downloadReplay(replay_url, allocator);
    defer replay.deinit(allocator);

    const audio = try downloadAudio(map_url, allocator);
    _ = audio;

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

    // albedo, emission, roughness
    rl.setMaterialTexture(&head_material, .albedo, head_texture);
    rl.setMaterialTexture(&left_saber_material, .albedo, left_saber_texture);
    rl.setMaterialTexture(&right_saber_material, .albedo, right_saber_texture);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
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

            // Head
            var position = replay.frames.items(.head_position)[frame_index];
            var rotation = rl.Quaternion.toMatrix(replay.frames.items(.head_rotation)[frame_index]);
            var transform = rl.Matrix.multiply(rotation, rl.Matrix.translate(position.x, position.y, position.z));
            var ray: rl.Ray = .{.position = position, .direction = FORWARD.transform(transform)};
            rl.drawMesh(head_mesh, head_material, transform);

            // Left hand
            position = replay.frames.items(.left_hand_position)[frame_index];
            rotation = rl.Quaternion.toMatrix(replay.frames.items(.left_hand_rotation)[frame_index]);
            transform = rl.Matrix.multiply(rotation, rl.Matrix.translate(position.x, position.y, position.z));
            rl.drawMesh(saber_hilt_mesh, left_saber_material, transform);
            ray = .{.position = position, .direction = FORWARD.transform(rotation)};
            rl.drawLine3D(position, position.add(ray.direction.scale(2)), .red);

            // Right hand
            position = replay.frames.items(.right_hand_position)[frame_index];
            rotation = rl.Quaternion.toMatrix(replay.frames.items(.right_hand_rotation)[frame_index]);
            transform = rl.Matrix.multiply(rotation, rl.Matrix.translate(position.x, position.y, position.z));
            rl.drawMesh(saber_hilt_mesh, right_saber_material, transform);
            ray = .{.position = position, .direction = FORWARD.transform(rotation)};
            rl.drawLine3D(position, position.add(ray.direction.scale(2)), .blue);

            rl.drawGrid(10, 0.5);
        }

        while (@as(f64, @floatCast(replay.frames.items(.time)[frame_index])) < rl.getTime()) {
            frame_index += 1;
        }
    }
}

