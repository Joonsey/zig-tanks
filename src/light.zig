const std = @import("std");
const rl = @import("raylib");
const ECS = @import("entity.zig").ECS;
const Entity = @import("entity.zig").Entity;
const SparseSet = @import("entity.zig").SparseSet;
const Light = @import("entity.zig").Light;
const Transform = @import("entity.zig").Transform;

const Camera = @import("camera.zig").Camera;
const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;

const LightRow = struct {
    entity: Entity,
    light: *Light,
    transform: *Transform,
};

pub const LightSystem = struct {
    arr: std.ArrayList(LightRow),
    camera: *Camera,

    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
        camera: *Camera,
    ) Self {
        return .{ .arr = std.ArrayList(LightRow).initCapacity(allocator, 25) catch unreachable, .camera = camera };
    }

    /// this function presumes that the shader is activated
    pub fn update_shader_values(self: *Self, shader: rl.Shader) void {
        const camera = self.camera.*;
        for (self.arr.items, 0..) |lr, i| {
            const transform = lr.transform;
            const light = lr.light;
            rl.setShaderValue(shader, rl.getShaderLocation(shader, rl.textFormat("lights[%i].position", .{i})), &camera.get_relative_position(transform.position).divide(.init(render_width, render_height)), .vec2);

            const height: f32 = @as(f32, @floatFromInt(light.height)) / 255.0;
            rl.setShaderValue(shader, rl.getShaderLocation(shader, rl.textFormat("lights[%i].height", .{i})), &height, .float);

            const radius: f32 = @as(f32, @floatFromInt(light.radius)) / 255.0;
            rl.setShaderValue(shader, rl.getShaderLocation(shader, rl.textFormat("lights[%i].radius", .{i})), &radius, .float);

            var color: rl.Vector3 = .{
                .x = @as(f32, @floatFromInt(light.color.r)) / 255.0,
                .y = @as(f32, @floatFromInt(light.color.g)) / 255.0,
                .z = @as(f32, @floatFromInt(light.color.b)) / 255.0,
            };
            color = color.scale(@as(f32, @floatFromInt(light.color.a)) / 255.0);
            rl.setShaderValue(shader, rl.getShaderLocation(shader, rl.textFormat("lights[%i].color", .{i})), &color, .vec3);
        }
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "light_count"), &self.arr.items.len, .int);
    }

    pub fn update(ctx: *anyopaque, ecs: *ECS) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        query_light_rows(self.camera.*, &ecs.transforms, &ecs.light, &self.arr);
    }

    fn query_light_rows(camera: Camera, transforms: *SparseSet(Transform), lights: *SparseSet(Light), out: *std.ArrayList(LightRow)) void {
        out.clearRetainingCapacity();

        for (lights.dense_entities.items, 0..) |e, i| {
            if (transforms.get(e)) |t| {
                // TODO guarantee capacity
                if (!camera.is_out_of_bounds(t.position)) out.appendAssumeCapacity(.{ .entity = e, .transform = t, .light = &lights.dense.items[i] });
            }
        }
    }
    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        self.arr.clearAndFree(allocator);
    }
};
