const std = @import("std");
const rl = @import("raylib");

const _entity = @import("entity.zig");
const ECS = _entity.ECS;
const Event = _entity.Event;
const Entity = _entity.Entity;
const SparseSet = _entity.SparseSet;
const RigidBody = _entity.RigidBody;
const Transform = _entity.Transform;
const Collider = _entity.Collider;
const Bullet = _entity.Bullet;
const EntityBitFlag = _entity.EntityBitFlag;

const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;

pub const TurretSystem = struct {
    map: std.AutoHashMap(Entity, Entity),
    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
    ) Self {
        return .{ .map = .init(allocator) };
    }

    // should only be called when instantiation a tank
    pub fn create(self: *Self, ecs: *ECS, base: Entity) void {
        if (ecs.transforms.get(base)) |base_t| {
            const new_turret = ecs.create();
            self.map.put(base, new_turret) catch unreachable;

            _ = ecs.transforms.add(new_turret, .{ .height = 3, .position = base_t.position, .rotation = 0 });
            _ = ecs.ssprite.add(new_turret, .TURRET_BASE);
            var flags = ecs.flags.add(new_turret, .empty());
            flags.set(.DontSaveToDisk);
        }
    }

    pub fn update(ctx: *anyopaque, ecs: *ECS) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        var iter = self.map.iterator();
        while (iter.next()) |e| {
            const base = e.key_ptr.*;
            const turret = e.value_ptr.*;

            if (ecs.transforms.get(turret)) |tt| {
                if (ecs.transforms.get(base)) |bt| {
                    tt.position = bt.position;
                }
            }
        }
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.map.clearAndFree();
    }
};
