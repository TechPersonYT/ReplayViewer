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

fn beatsToSeconds(beats: f32, bpm: f32) f32 {
    const beat_duration = 60.0 / bpm;
    return beats * beat_duration;
}

fn beatsToMeters(beats: f32, bpm: f32, njs: f32) f32 {
    return beatsToSeconds(beats, bpm) * njs;
}

pub const NoteJumpInfo = struct {
    njs: f32,
    nso: f32,
    bpm: f32,
    jump_distance: f32,
    jump_duration: f32,
    half_jump_duration: f32,
    jump_z_position: f32,

    // Thanks Mawntee! https://discord.com/channels/864661281268039700/864661281730330626/1436597181300609045
    pub fn fromSpeedOffsetBpm(njs: f32, nso: f32, bpm: f32) NoteJumpInfo {
        const start_half_jump_duration: f32 = 4.0;
        const max_half_jump_duration: f32 = 18.0 - 0.001;
        const beat_duration: f32 = 60.0 / bpm;

        var half_jump_duration = start_half_jump_duration;

        // meters / beat
        const njs_mpb = njs * beat_duration;
        const max_half_jump_duration_scaled = max_half_jump_duration / njs_mpb;

        while (half_jump_duration > max_half_jump_duration_scaled) {
            half_jump_duration *= 0.5;
        }

        half_jump_duration += nso;
        half_jump_duration = @max(0.25, half_jump_duration);

        const jump_duration = half_jump_duration * 2.0 * beat_duration;
        const jump_distance = njs * jump_duration;
        const jump_z_position = jump_distance * 0.5 + 1.0;

        return .{
            .njs = njs,
            .nso = nso,
            .bpm = bpm,
            .jump_distance = jump_distance,
            .jump_duration = jump_duration,
            .half_jump_duration = half_jump_duration,
            .jump_z_position = jump_z_position
        };
    }
};

pub fn getTimedNotePose(placement: Placement, direction: CutDirection, time: f32, jump_info: NoteJumpInfo, flip: bool) struct { rl.Vector3, rl.Matrix } {
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

    const unclamped_jump_progress = jump_info.half_jump_duration - placement.time + time;
    const jump_progress = @min(@max(unclamped_jump_progress, 0.0), 1.0);
    const rotation_progress = @min(jump_progress * 4.0, 1.0);
    const rotation = std.math.lerp(std.math.pi, final_rotation, tweens.easeOutQuad(rotation_progress));

    const flip_progress = @min(jump_progress * 2.0, 1.0);
    const x = if (flip) std.math.lerp(-placement.x, placement.x, tweens.easeOutQuad(flip_progress)) else placement.x;

    const y = std.math.lerp(0.0, placement.y, tweens.easeOutQuad(jump_progress));

    const z = jump_info.njs * (placement.time - time) - beatsToMeters(jump_info.nso, jump_info.bpm, jump_info.njs) * 0.5;

    const position: rl.Vector3 = .init(x * UNITS_TO_METERS, y * UNITS_TO_METERS + UNITS_TO_METERS - 1.0, z);

    // TODO: Notes should yaw rotate to look at the player during the jump
    const m = rl.Matrix.multiply(rl.Matrix.rotateZ(rotation), rl.Matrix.translate(position.x, position.y, position.z));

    return .{ position, m };
}
