const rl = @import("raylib");

pub fn main() anyerror!void {
    // Initialization
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "Beat Leader Replay Viewer (Prototype)");
    defer rl.closeWindow(); // Close window and OpenGL context

    var camera = rl.Camera{
        .position = .init(10, 10, 10),
        .target = .init(0, 0, 0),
        .up = .init(0, 1, 0),
        .fovy = 70,
        .projection = .perspective,
    };

    const cube_position = rl.Vector3.init(0, 0, 0);

    rl.setTargetFPS(120);

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

            rl.drawCube(cube_position, 2, 2, 2, .red);
            rl.drawGrid(10, 1);
        }
    }
}

