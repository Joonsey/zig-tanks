const std = @import("std");
const rl = @import("raylib");

const assets = @import("assets.zig");
const Camera = @import("camera.zig").Camera;

const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;
const MAX_ENTITY_COUNT = consts.MAX_ENTITY_COUNT;

pub const Transform = extern struct {
    position: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
};

pub const Entity = u32;

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

pub const ECS = struct {
    const System = struct {
        ctx: *anyopaque,
        update_fn: *const fn (ctx: *anyopaque, ecs: *Self) void,
    };

    transforms: SparseSet(Transform),
    ssprite: SparseSet(assets.Assets),
    light: SparseSet(Light),
    collider: SparseSet(Collider),

    next: Entity = 0,
    free_entities: std.ArrayList(Entity),

    allocator: std.mem.Allocator,

    systems: std.ArrayList(System) = .{},

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .transforms = .init(allocator, MAX_ENTITY_COUNT),
            .ssprite = .init(allocator, MAX_ENTITY_COUNT),
            .light = .init(allocator, MAX_ENTITY_COUNT),
            .collider = .init(allocator, MAX_ENTITY_COUNT),

            .free_entities = std.ArrayList(Entity).initCapacity(allocator, MAX_ENTITY_COUNT) catch unreachable,
            .allocator = allocator,
        };
    }

    pub fn add_system(self: *Self, system: System) void {
        self.systems.append(self.allocator, system) catch unreachable;
    }

    pub fn create(self: *Self) Entity {
        if (self.free_entities.items.len > 0) {
            return self.free_entities.pop().?;
        }
        const id = self.next;
        self.next += 1;
        return id;
    }

    pub fn copy(self: *Self, e: Entity) Entity {
        const ne = self.create();

        if (self.light.get(e)) |l| _ = self.light.add(ne, l.*);
        if (self.transforms.get(e)) |l| _ = self.transforms.add(ne, l.*);
        if (self.ssprite.get(e)) |l| _ = self.ssprite.add(ne, l.*);
        if (self.collider.get(e)) |l| _ = self.collider.add(ne, l.*);

        return ne;
    }

    pub fn destroy(self: *Self, e: Entity) void {
        // TODO guarantee capacity
        self.free_entities.appendAssumeCapacity(e);

        self.light.remove(e);
        self.transforms.remove(e);
        self.ssprite.remove(e);
        self.collider.remove(e);
    }

    pub fn query_light_rows(camera: Camera, transforms: *SparseSet(Transform), lights: *SparseSet(Light), out: *std.ArrayList(LightRow)) void {
        out.clearRetainingCapacity();

        for (lights.dense_entities.items, 0..) |e, i| {
            if (transforms.get(e)) |t| {
                // TODO guarantee capacity
                if (!camera.is_out_of_bounds(t.position)) out.appendAssumeCapacity(.{ .entity = e, .transform = t, .light = &lights.dense.items[i] });
            }
        }
    }

    pub fn update(self: *Self) void {
        for (self.systems.items) |system| system.update_fn(system.ctx, self);
    }

    pub fn free(self: *Self) void {
        self.ssprite.deinit(self.allocator);
        self.transforms.deinit(self.allocator);
        self.light.deinit(self.allocator);
        self.collider.deinit(self.allocator);

        self.free_entities.clearAndFree(self.allocator);

        self.systems.clearAndFree(self.allocator);
    }

    pub fn debug(self: *Self) void {
        std.log.debug("ECS DEBUG START", .{});
        for (0..self.next) |ue| {
            const e: Entity = @intCast(ue);
            std.log.debug("{?} | {?} | {?} | {?}", .{
                self.transforms.get(e),
                self.light.get(e),
                self.ssprite.get(e),
                self.collider.get(e),
            });
        }
    }

    const MAGIC = 0x4C564C88;
    pub fn load(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var buffer: [1024]u8 = std.mem.zeroes([1024]u8);
        _ = try file.read(&buffer);
        var reader = std.io.Reader.fixed(&buffer);

        const version = try reader.takeInt(u8, .little);
        const magic = try reader.takeInt(u32, .little);

        if (version != 1) @panic("TODO");
        if (magic != MAGIC) @panic("Magic bytes not matching");

        const number_of_entities = try reader.takeInt(u32, .little);
        for (0..number_of_entities) |_| {
            const e = self.create();
            var component = try reader.takeInt(u8, .little);
            while (component > 0) {
                switch (component) {
                    // transform
                    1 => _ = self.transforms.add(e, try reader.takeStruct(Transform, .little)),
                    // ssprite
                    2 => {
                        const s = try reader.takeInt(u32, .little);
                        _ = self.ssprite.add(e, @enumFromInt(s));
                    },
                    // light
                    3 => _ = self.light.add(e, try reader.takeStruct(Light, .little)),
                    4 => {
                        const r = try reader.takeInt(u8, .little);
                        switch (r) {
                            1 => _ = self.collider.add(e, .{ .Circle = @bitCast(try reader.takeInt(u32, .little)) }),
                            2 => _ = self.collider.add(e, .{ .Rectangle = try reader.takeStruct(rl.Vector2, .little) }),
                            else => std.log.warn("got unexpected collider id {d}", .{r}),
                        }
                    },
                    else => std.log.warn("got unexpected component id {d}", .{component}),
                }
                component = try reader.takeInt(u8, .little);
            }
        }
    }

    pub fn save(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var buffer: [1024]u8 = std.mem.zeroes([1024]u8);
        var writer = std.io.Writer.fixed(&buffer);

        try writer.writeInt(u8, 1, .little);
        try writer.writeInt(u32, MAGIC, .little);

        const entities = self.transforms.dense_entities.items;

        try writer.writeInt(u32, @intCast(entities.len), .little);
        for (entities) |e| {
            if (self.transforms.get(e)) |t| {
                try writer.writeInt(u8, 1, .little);
                try writer.writeStruct(t.*, .little);
            }
            if (self.ssprite.get(e)) |s| {
                try writer.writeInt(u8, 2, .little);
                try writer.writeInt(u32, @intFromEnum(s.*), .little);
            }
            if (self.light.get(e)) |l| {
                try writer.writeInt(u8, 3, .little);
                try writer.writeStruct(l.*, .little);
            }
            if (self.collider.get(e)) |c| {
                try writer.writeInt(u8, 4, .little);
                switch (c.*) {
                    .Circle => |r| {
                        try writer.writeInt(u8, 1, .little);
                        const bits: u32 = @bitCast(r);
                        try writer.writeInt(u32, bits, .little);
                    },
                    .Rectangle => |r| {
                        try writer.writeInt(u8, 2, .little);
                        try writer.writeStruct(r, .little);
                    },
                }
            }

            try writer.writeInt(u8, 0, .little);
        }
        _ = try file.write(buffer[0..writer.end]);
    }
};

const Light = extern struct {
    height: u8,
    radius: u8 = 120,
    color: rl.Color,
};

const LightRow = struct {
    entity: Entity,
    light: *Light,
    transform: *Transform,
};

pub const LightSystem = struct {
    arr: std.ArrayList(LightRow),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .arr = std.ArrayList(LightRow).initCapacity(allocator, 25) catch unreachable };
    }

    /// this function presumes that the shader is activated
    pub fn update_shader_values(self: *Self, camera: Camera, shader: rl.Shader, ecs: *ECS) void {
        ECS.query_light_rows(camera, &ecs.transforms, &ecs.light, &self.arr);
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

    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        self.arr.clearAndFree(allocator);
    }
};

// Collisions are always around the center position of the object
// i am opting to do this because we don't need the 'position' from raylib
// aditionaly they need to be fine-tuned as they need to be rotated and i don't think a simple AABB
// rotation will suffice for rectangular collisions.
// in the instance for Rectangle, the X and Y are in radius, not diameter. Along each axis.
const Collider = union(enum) {
    Circle: f32,
    Rectangle: rl.Vector2,
};
