const std = @import("std");
const consts = @import("../consts.zig");

pub const Entity = consts.Entity;

pub fn SparseSet(comptime T: type) type {
    return struct {
        dense_entities: std.ArrayList(Entity),
        dense: std.ArrayList(T),
        sparse: []usize,

        const invalid = std.math.maxInt(usize);

        pub fn init(
            allocator: std.mem.Allocator,
            max_entities: usize,
        ) @This() {
            const sparse = allocator.alloc(usize, max_entities) catch unreachable;
            @memset(sparse, invalid);

            return .{
                .dense_entities = std.ArrayList(Entity).initCapacity(allocator, max_entities) catch unreachable,
                .dense = std.ArrayList(T).initCapacity(allocator, max_entities) catch unreachable,
                .sparse = sparse,
            };
        }

        pub fn add(self: *@This(), e: Entity, value: T) *T {
            const idx = self.dense.items.len;
            self.sparse[e] = idx;

            self.dense_entities.appendAssumeCapacity(e);
            self.dense.appendAssumeCapacity(value);

            return &self.dense.items[idx];
        }

        pub fn remove(self: *@This(), e: Entity) void {
            const idx = self.sparse[e];
            if (idx == invalid) return;

            const last = self.dense.items.len - 1;

            if (idx != last) {
                self.dense.items[idx] = self.dense.items[last];
                const moved = self.dense_entities.items[last];
                self.dense_entities.items[idx] = moved;
                self.sparse[moved] = idx;
            }

            _ = self.dense.pop();
            _ = self.dense_entities.pop();
            self.sparse[e] = invalid;
        }

        pub fn has(self: *@This(), e: Entity) bool {
            return self.sparse[e] != invalid;
        }

        pub fn get(self: *@This(), e: Entity) ?*T {
            const idx = self.sparse[e];
            if (idx == invalid) return null;
            return &self.dense.items[idx];
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.dense_entities.deinit(allocator);
            self.dense.deinit(allocator);
            allocator.free(self.sparse);
        }
    };
}
