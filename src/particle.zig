const std = @import("std");
const rl = @import("raylib");

const _entity = @import("entity.zig");
const ECS = _entity.ECS;
const Entity = _entity.Entity;
const SparseSet = _entity.SparseSet;
const RigidBody = _entity.RigidBody;
const Transform = _entity.Transform;
const Collider = _entity.Collider;
const Event = _entity.Event;

const Camera = @import("camera.zig").Camera;

const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;

pub const ParticleSystem = struct {
    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
    ) Self {
        _ = allocator;
        return .{};
    }

    pub fn on_event(ctx: *anyopaque, event: Event, ecs: *ECS) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const dt = rl.getFrameTime();
        _ = self;

        switch (event) {
            .Collision => |c| {
                if (ecs.bullet.get(c.e)) |_| {
                    if (ecs.collider.get(c.other)) |other_c| if (other_c.mode == .Trigger) return;
                    if (ecs.transforms.get(c.e)) |t| {
                        const max: f32 = @divTrunc(c.velocity.length(), 100);
                        for (0..@intFromFloat(max)) |i| {
                            const new_particle = ecs.create();
                            _ = ecs.transforms.add(new_particle, t.*);
                            _ = ecs.particle.add(new_particle, .{ .color = .blue });
                            _ = ecs.collider.add(new_particle, .{ .shape = .{ .Rectangle = .init(2, 2) }, .mode = .Trigger });
                            _ = ecs.ssprite.add(new_particle, .PARTICLE);
                            // _ = ecs.light.add(new_particle, .{ .height = 2, .color = .white, .radius = 2 });
                            var rb = ecs.rigidbody.add(new_particle, .{});

                            const fi: f32 = @floatFromInt(i);
                            const offset = fi / max * std.math.pi;
                            const x: f32 = @floatCast(@sin(offset + rl.getTime()) * std.math.pi);
                            const y: f32 = @floatCast(@sin(offset + rl.getTime()) * std.math.pi);

                            rb.impulse = .init(x, y);
                            rb.impulse = rb.impulse.scale(20);
                        }
                    }
                }

                if (ecs.particle.get(c.e)) |_| {
                    if (ecs.rigidbody.get(c.e)) |rb| {
                        if (ecs.transforms.get(c.e)) |t| {
                            if (ecs.collider.get(c.other)) |other_c| if (other_c.mode == .Trigger) return;
                            t.position = t.position.subtract(rb.velocity.scale(dt));
                            // COPY PASTED FROM BULLETS
                            switch (c.axis) {
                                // TODO something is going on when flipping on X axis, makes it re-collide and swap both axis directions unexpectedly
                                // this is a temporary fix, but at least a fix
                                .X => rb.velocity = rb.velocity.scale(-1),
                                .Y => rb.velocity.y = -rb.velocity.y,
                            }

                            const normalized_velocity = rb.velocity.normalize();
                            const rotation = std.math.atan2(normalized_velocity.y, normalized_velocity.x);

                            t.rotation = rotation;
                        }
                    }
                }
            },
        }
    }

    pub fn update(ctx: *anyopaque, ecs: *ECS) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const dt = rl.getFrameTime();

        _ = self;

        for (ecs.particle.dense_entities.items) |e| {
            const particle = ecs.particle.get(e).?;
            particle.remaining -= dt;

            if (particle.remaining <= 0) {
                ecs.destroy(e);
                continue;
            }
        }
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
