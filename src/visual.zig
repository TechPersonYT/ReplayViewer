const std = @import("std");
const rl = @import("raylib");
const rp = @import("replay.zig");
const tweens = @import("tweens.zig");
const Placement = @import("common.zig").Placement;
const CutDirection = @import("common.zig").CutDirection;

const CUBE_SIDE_LENGTH: f32 = 0.5;

const UNITS_TO_METERS: f32 = 0.6;
const METERS_TO_UNITS: f32 = 1.0 / UNITS_TO_METERS;

const SABER_LENGTH: f32 = 1.0 * METERS_TO_UNITS;

const NoteJumpInfo = struct {
    jump_distance: f32,
    jump_duration: f32,
    jump_z_position: f32,
};

// Thanks Mawntee! https://discord.com/channels/864661281268039700/864661281730330626/1436597181300609045
pub fn getNoteJumpInfo(njs: f32, njo: f32, bpm: f32) NoteJumpInfo {
    const start_half_jump_duration = 4.0;
    const max_half_jump_duration = 18.0 - 0.001;
    const beat_duration = 60.0 / bpm;

    var half_jump_duration = start_half_jump_duration;

    // meters / beat
    const njs_mpb = njs * beat_duration;
    const max_half_jump_duration_scaled = max_half_jump_duration / njs_mpb;

    while (half_jump_duration > max_half_jump_duration_scaled) {
        half_jump_duration *= 0.5;
    }

    half_jump_duration += njo;
    half_jump_duration = @max(0.25, half_jump_duration);

    const jump_duration = half_jump_duration * 2.0 * beat_duration;
    const jump_distance = njs * jump_duration;
    const jump_z_position = jump_distance * 0.5 + 1.0;

    return .{
        .jump_distance = jump_distance,
        .jump_duration = jump_duration,
        .jump_z_position = jump_z_position,
    };
}

pub fn getNoteJumpInfo2(njs: f32, jump_distance: f32) NoteJumpInfo {
    return .{
        .jump_distance = jump_distance,
        .jump_duration = jump_distance * 0.5 / njs,
        .jump_z_position = jump_distance * 0.5 + 1.0,
    };
}

pub fn getTimedNotePose(placement: Placement, direction: CutDirection, time: f32, jump_info: NoteJumpInfo, crossover: bool) rl.Matrix {
    const final_rotation: f32 = switch (direction) {
        .up => 0.0,
        .down => std.math.pi,
        .left => std.math.pi * -0.5,
        .right => std.math.pi * 0.5,

        .up_left => std.math.pi * -0.25,
        .up_right => std.math.pi * 0.25,
        .down_left => std.math.pi * -0.75,
        .down_right => std.math.pi * 0.75,

        else => 0.0,
    };

    const unclamped_jump_progress = jump_info.jump_duration - placement.time + time;
    const jump_progress = @min(@max(unclamped_jump_progress, 0.0), 1.0);
    const rotation_progress = @min(jump_progress * 8.0, 1.0);
    const rotation = std.math.lerp(std.math.pi, final_rotation, tweens.easeOutQuad(rotation_progress));

    const final_x: f32 = 1.5 - @as(f32, @floatFromInt(placement.line_index));
    const final_y: f32 = @floatFromInt(placement.line_layer);

    const flip_progress = @min(jump_progress * 4.0, 1.0);
    const x = if (crossover) std.math.lerp(-final_x, final_x, tweens.easeOutQuad(flip_progress)) else final_x;

    const half_jump_progress = @min(jump_progress * 2.0, 1.0);
    const y = std.math.lerp(0.0, final_y, tweens.easeOutQuad(half_jump_progress));

    const z = if (unclamped_jump_progress < 0.0) std.math.lerp(jump_info.jump_distance, 100.0, unclamped_jump_progress * -1.0) else std.math.lerp(jump_info.jump_distance, 0.0, tweens.easeOutQuad(unclamped_jump_progress * 2.0));

    // TODO: Notes should yaw rotate to look at the player during the jump
    return rl.Matrix.multiply(rl.Matrix.rotateZ(rotation), rl.Matrix.translate(x * UNITS_TO_METERS, y * UNITS_TO_METERS + 1.0, z * UNITS_TO_METERS));
}
