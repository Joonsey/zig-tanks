const std = @import("std");
const rl = @import("raylib");
const ECS = @import("entity.zig").ECS;
const Entity = @import("entity.zig").Entity;
const SparseSet = @import("entity.zig").SparseSet;
const RigidBody = @import("entity.zig").RigidBody;
const Transform = @import("entity.zig").Transform;
const Collider = @import("entity.zig").Collider;

const Camera = @import("camera.zig").Camera;
const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;

const PhysicsRow = struct {
    entity: Entity,
    rigidbody: *RigidBody,
    transform: *Transform,
};

pub const PhysicsSystem = struct {
    arr: std.ArrayList(PhysicsRow),

    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
    ) Self {
        return .{
            .arr = std.ArrayList(PhysicsRow).initCapacity(allocator, 250) catch unreachable,
        };
    }

    pub fn update(ctx: *anyopaque, ecs: *ECS) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        query_physics_rows(&ecs.transforms, &ecs.rigidbody, &self.arr);

        const dt = rl.getFrameTime();
        for (self.arr.items) |row| {
            const rb = row.rigidbody;
            const t = row.transform;
            const e = row.entity;

            rb.velocity = rb.velocity.add(rb.impulse.scale(rb.inv_mass));

            rb.velocity = rb.velocity.add(rb.force.scale(dt * rb.inv_mass));

            const frame_damping = std.math.pow(f32, rb.damping, dt);
            rb.velocity = rb.velocity.scale(frame_damping);

            const projected_position = t.position.add(rb.velocity.scale(dt));

            if (ecs.collider.get(e)) |c| {
                if (rb.velocity.length() == 0) break;

                const start_velocity = rb.velocity;
                t.position.x = projected_position.x;
                for (ecs.collider.dense_entities.items) |other_e| {
                    if (other_e == e) continue;

                    const other_c = ecs.collider.get(other_e).?;
                    if (ecs.transforms.get(other_e)) |other_t| {
                        if (colliding(.{ .collider = c.*, .transform = t }, .{ .collider = other_c.*, .transform = other_t })) {
                            if (rb.velocity.x > 0) {
                                t.position.x = other_t.position.x - (switch (other_c.*) {
                                    .Circle => |r| r,
                                    .Rectangle => |r| r.x,
                                } + switch (c.*) {
                                    .Circle => |r| r,
                                    .Rectangle => |r| r.x,
                                }) / 2;
                            } else {
                                t.position.x = other_t.position.x + (switch (other_c.*) {
                                    .Circle => |r| r,
                                    .Rectangle => |r| r.x,
                                } + switch (c.*) {
                                    .Circle => |r| r,
                                    .Rectangle => |r| r.x,
                                }) / 2;
                            }
                            rb.velocity.x = 0;
                            ecs.push_event(.{ .Collision = .{ .e = e, .other = other_e, .velocity = start_velocity, .axis = .X } });
                            break;
                        }
                    }
                }
                t.position.y = projected_position.y;
                for (ecs.collider.dense_entities.items) |other_e| {
                    if (other_e == e) continue;

                    const other_c = ecs.collider.get(other_e).?;
                    if (ecs.transforms.get(other_e)) |other_t| {
                        if (colliding(.{ .collider = c.*, .transform = t }, .{ .collider = other_c.*, .transform = other_t })) {
                            if (rb.velocity.y > 0) {
                                t.position.y = other_t.position.y - (switch (other_c.*) {
                                    .Circle => |r| r,
                                    .Rectangle => |r| r.y,
                                } + switch (c.*) {
                                    .Circle => |r| r,
                                    .Rectangle => |r| r.y,
                                }) / 2;
                            } else {
                                t.position.y = other_t.position.y + (switch (other_c.*) {
                                    .Circle => |r| r,
                                    .Rectangle => |r| r.y,
                                } + switch (c.*) {
                                    .Circle => |r| r,
                                    .Rectangle => |r| r.y,
                                }) / 2;
                            }
                            rb.velocity.y = 0;
                            ecs.push_event(.{ .Collision = .{ .e = e, .other = other_e, .velocity = start_velocity, .axis = .Y } });
                            break;
                        }
                    }
                }
            } else {
                t.position = projected_position;
            }

            if (rb.velocity.scale(dt).length() < 0.001) rb.velocity = .zero();
            rb.force = .zero();
            rb.impulse = .zero();
        }
    }

    fn query_physics_rows(transforms: *SparseSet(Transform), rigidbody: *SparseSet(RigidBody), out: *std.ArrayList(PhysicsRow)) void {
        out.clearRetainingCapacity();

        for (rigidbody.dense_entities.items, 0..) |e, i| {
            if (transforms.get(e)) |t| {
                out.appendAssumeCapacity(.{ .entity = e, .transform = t, .rigidbody = &rigidbody.dense.items[i] });
            }
        }
    }
    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        self.arr.clearAndFree(allocator);
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
        .Rectangle => |r| c.transform.position.distance(other.transform.position) < @max(r.x, r.y),
    };
}
