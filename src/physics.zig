const std = @import("std");
const rl = @import("raylib");
const ECS = @import("entity.zig").ECS;
const _entity = @import("entity.zig");
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

    pub fn on_event(ctx: *anyopaque, event: Event, ecs: *ECS) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const dt = rl.getFrameTime();
        _ = dt;
        _ = self;

        switch (event) {
            .Collision => |c| {
                if (ecs.collider.get(c.other)) |other_c| if (other_c.mode == .Trigger) return;
                if (ecs.particle.get(c.e)) |_| return;
                if (ecs.rigidbody.get(c.other)) |rb| {
                    var impulse = c.velocity;
                    if (ecs.transforms.get(c.other)) |other_t| {
                        if (ecs.transforms.get(c.e)) |t| {
                            const direction = other_t.position.subtract(t.position).normalize();
                            const magnitude = c.velocity.length();
                            impulse = direction.scale(magnitude);
                        }
                    }

                    rb.impulse = impulse;
                }
            },
        }
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
                if (rb.velocity.length() == 0) continue;

                const start_velocity = rb.velocity;
                t.position.x = projected_position.x;
                for (ecs.collider.dense_entities.items) |other_e| {
                    if (other_e == e) continue;

                    const other_c = ecs.collider.get(other_e).?;
                    if (ecs.transforms.get(other_e)) |other_t| {
                        if (colliding(.{ .collider = c.*, .transform = t }, .{ .collider = other_c.*, .transform = other_t })) {
                            if (other_c.mode == .Solid and c.mode == .Solid) {
                                if (rb.velocity.x > 0) {
                                    t.position.x = other_t.position.x - (switch (other_c.shape) {
                                        .Circle => |r| r,
                                        .Rectangle => |r| r.x,
                                    } + switch (c.shape) {
                                        .Circle => |r| r,
                                        .Rectangle => |r| r.x,
                                    });
                                } else {
                                    t.position.x = other_t.position.x + (switch (other_c.shape) {
                                        .Circle => |r| r,
                                        .Rectangle => |r| r.x,
                                    } + switch (c.shape) {
                                        .Circle => |r| r,
                                        .Rectangle => |r| r.x,
                                    });
                                }
                                rb.velocity.x = 0;
                            }
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
                            if (other_c.mode == .Solid and c.mode == .Solid) {
                                if (rb.velocity.y > 0) {
                                    t.position.y = other_t.position.y - (switch (other_c.shape) {
                                        .Circle => |r| r,
                                        .Rectangle => |r| r.y,
                                    } + switch (c.shape) {
                                        .Circle => |r| r,
                                        .Rectangle => |r| r.y,
                                    });
                                } else {
                                    t.position.y = other_t.position.y + (switch (other_c.shape) {
                                        .Circle => |r| r,
                                        .Rectangle => |r| r.y,
                                    } + switch (c.shape) {
                                        .Circle => |r| r,
                                        .Rectangle => |r| r.y,
                                    });
                                }
                                rb.velocity.y = 0;
                            }
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
    return switch (c.collider.shape) {
        .Circle => |r| c.transform.position.distance(other.transform.position) < r,
        .Rectangle => |r| switch (other.collider.shape) {
            .Circle => |ir| c.transform.position.distance(other.transform.position) < ir,
            .Rectangle => |ir| rl.Rectangle.init(
                c.transform.position.x - r.x,
                c.transform.position.y - r.y,
                r.x * 2,
                r.y * 2,
            ).checkCollision(rl.Rectangle.init(
                other.transform.position.x - ir.x,
                other.transform.position.y - ir.y,
                ir.x * 2,
                ir.y * 2,
            )),
        },
    };
}
