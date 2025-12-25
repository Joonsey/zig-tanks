const std = @import("std");
const rl = @import("raylib");

const ECS = @import("entity.zig").ECS;
const Event = @import("entity.zig").Event;
const Entity = @import("entity.zig").Entity;
const SparseSet = @import("entity.zig").SparseSet;
const RigidBody = @import("entity.zig").RigidBody;
const Transform = @import("entity.zig").Transform;
const Collider = @import("entity.zig").Collider;
const Bullet = @import("entity.zig").Bullet;

const Camera = @import("camera.zig").Camera;
const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;

const BULLET_SPEED = 200;

pub const BulletSystem = struct {
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
                const e = c.e;
                if (ecs.bullet.get(e)) |_| {
                    if (ecs.bullet.get(c.other)) |_| {
                        ecs.destroy(e);
                        ecs.destroy(c.other);
                        return;
                    }
                    if (ecs.rigidbody.get(e)) |rb| {
                        if (ecs.transforms.get(e)) |t| {
                            t.position = t.position.subtract(rb.velocity.scale(dt));

                            switch (c.axis) {
                                .X => rb.velocity.x = -rb.velocity.x,
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

    pub fn add(self: *Self, owner: Entity, bullet: Bullet, ecs: *ECS) void {
        _ = self;
        if (ecs.transforms.get(owner)) |t| {
            const new_bullet = ecs.create();

            const new_bullet_transform = ecs.transforms.add(new_bullet, t.*);
            const new_bullet_collider = ecs.collider.add(new_bullet, .{ .shape = .{ .Rectangle = .init(4, 4) }, .mode = .Trigger });
            const rb = ecs.rigidbody.add(new_bullet, .{ .damping = 1 });

            const forward: rl.Vector2 = .{
                .x = @cos(t.rotation),
                .y = @sin(t.rotation),
            };
            rb.velocity = forward.scale(BULLET_SPEED);

            const owner_radius = if (ecs.collider.get(owner)) |c| switch (c.shape) {
                .Rectangle => |r| @max(r.x, r.y),
                .Circle => |r| r,
            } else 0;

            const bullet_radius = switch (new_bullet_collider.shape) {
                .Rectangle => |r| @max(r.x, r.y),
                .Circle => |r| r,
            };

            const denormalized_forward: rl.Vector2 = .{
                .x = if (forward.x < 0.5 and forward.x > -0.5) 0 else if (forward.x > 0) 1 else -1,
                .y = if (forward.y < 0.5 and forward.y > -0.5) 0 else if (forward.y > 0) 1 else -1,
            };
            // idk. this works though but looks messy asf
            const margin = 1 + denormalized_forward.length() * 2;
            new_bullet_transform.position = new_bullet_transform.position.add(forward.scale(owner_radius + bullet_radius + margin));

            _ = ecs.ssprite.add(new_bullet, .BULLET);
            _ = ecs.bullet.add(new_bullet, bullet);
            _ = ecs.light.add(new_bullet, .{ .color = .red, .height = 15, .radius = 50 });
        }
    }

    pub fn update(ctx: *anyopaque, ecs: *ECS) void {
        const dt = rl.getFrameTime();
        const self: *Self = @ptrCast(@alignCast(ctx));
        for (ecs.bullet.dense_entities.items) |e| {
            const bullet = ecs.bullet.get(e).?;
            bullet.remaining -= dt;
            if (bullet.remaining <= 0) {
                ecs.destroy(e);
            }
        }
        _ = self;
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

const CollisionBody = struct {
    collider: Collider,
    transform: *Transform,
};

// TODO make this good
// use SAT
fn colliding(c: CollisionBody, other: CollisionBody) bool {
    return switch (c.collider) {
        .Circle => |r| c.transform.position.distance(other.transform.position) < r,
        .Rectangle => |r| switch (other.collider) {
            .Circle => |ir| c.transform.position.distance(other.transform.position) < ir,
            .Rectangle => |ir| rl.Rectangle.init(c.transform.position.x, c.transform.position.y, r.x * 2, r.y * 2).checkCollision(rl.Rectangle.init(other.transform.position.x, other.transform.position.y, ir.x * 2, ir.y * 2)),
        },
    };
}
