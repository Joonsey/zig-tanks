const std = @import("std");
const rl = @import("raylib");

const assets = @import("assets.zig");
const Level = @import("level.zig").Level;

const Camera = @import("camera.zig").Camera;

const window_height = 720;
const window_width = 1080;

const render_height = window_height / 4;
const render_width = window_width / 4;

var discreete_render_texture: rl.RenderTexture = undefined;
var normal_render_texture: rl.RenderTexture = undefined;
var height_render_texture: rl.RenderTexture = undefined;

var normal_shader: rl.Shader = undefined;
var height_shader: rl.Shader = undefined;

pub const Transform = struct {
    position: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
};

// this is much more performant than the previous implement
// leaving it currently at 150fps @ 1000 entities
// previous implementation had 60fps @ 1000 entities
fn draw_system_function(camera: Camera, query: []RenderRow) void {
    discreete_render_texture.begin();
    for (query) |q| stack_draw(q.sprite.texture, q.transform.rotation - camera.rotation, camera.get_relative_position(q.transform.position));
    discreete_render_texture.end();

    normal_render_texture.begin();
    for (query) |q| {
        const position = camera.get_relative_position(q.transform.position);
        const rotation = q.transform.rotation - camera.rotation;
        const s = q.sprite;
        normal_shader.activate();
        // passing in absolute 'rotation'
        // I think this is correct, it's world space rotation, it looks right!
        rl.setShaderValue(normal_shader, rl.getShaderLocation(normal_shader, "rotation"), &rotation, .float);
        stack_draw(s.normals, rotation, position);
        normal_shader.deactivate();
    }
    normal_render_texture.end();
}

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

const MAX_ENTITY_COUNT = 10000;

const RenderRow = struct {
    entity: Entity,
    transform: *Transform,
    sprite: *assets.SSprite,
};

const ECS = struct {
    transforms: SparseSet(Transform),
    ssprite: SparseSet(*assets.SSprite),
    light: SparseSet(Light),

    render_rows: std.ArrayList(RenderRow),

    next: Entity = 0,
    free_entities: std.ArrayList(Entity),

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .transforms = .init(allocator, MAX_ENTITY_COUNT),
            .ssprite = .init(allocator, MAX_ENTITY_COUNT),
            .light = .init(allocator, MAX_ENTITY_COUNT),

            .render_rows = std.ArrayList(RenderRow).initCapacity(allocator, MAX_ENTITY_COUNT) catch unreachable,

            .free_entities = std.ArrayList(Entity).initCapacity(allocator, MAX_ENTITY_COUNT) catch unreachable,
            .allocator = allocator,
        };
    }

    pub fn create(self: *Self) Entity {
        if (self.free_entities.items.len > 0) {
            return self.free_entities.pop().?;
        }
        const id = self.next;
        self.next += 1;
        return id;
    }

    pub fn destroy(self: *Self, e: Entity) void {
        // TODO guarantee capacity
        self.free_entities.appendAssumeCapacity(e);

        self.light.remove(e);
        self.transforms.remove(e);
        self.ssprite.remove(e);
    }

    fn query_render_rows(camera: Camera, transforms: *SparseSet(Transform), sprites: *SparseSet(*assets.SSprite), out: *std.ArrayList(RenderRow)) void {
        out.clearRetainingCapacity();

        for (sprites.dense_entities.items, 0..) |e, i| {
            if (transforms.get(e)) |t| {
                // TODO guarantee capacity
                if (!camera.is_out_of_bounds(t.position)) out.appendAssumeCapacity(.{ .entity = e, .transform = t, .sprite = sprites.dense.items[i] });
            }
        }
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

    pub fn render(self: *Self, camera: Camera) void {
        // TODO implement the 'S' part of the ECS
        // would be sick if we could reflect on the parameters and add them dynamically
        query_render_rows(camera, &self.transforms, &self.ssprite, &self.render_rows);

        std.mem.sort(RenderRow, self.render_rows.items, camera, order_by_camera_position);
        draw_system_function(camera, self.render_rows.items);
    }

    pub fn free(self: *Self) void {
        self.ssprite.deinit(self.allocator);
        self.transforms.deinit(self.allocator);
        self.light.deinit(self.allocator);

        self.render_rows.clearAndFree(self.allocator);
        self.free_entities.clearAndFree(self.allocator);
    }

    pub fn debug(self: *Self) void {
        std.log.debug("ECS DEBUG START", .{});
        for (0..self.next) |ue| {
            const e: Entity = @intCast(ue);
            std.log.debug("{?} | {?} | {?*}", .{
                self.transforms.get(e),
                self.light.get(e),
                if (self.ssprite.get(e)) |s| s.* else null,
            });
        }
        std.log.debug("number of renderables last frame: {d}", .{self.render_rows.items.len});
    }
};

fn stack_draw(texture: rl.Texture, rotation: f32, position: rl.Vector2) void {
    const width = texture.width;
    const rows: usize = @intCast(@divTrunc(texture.height, width));
    const f_width: f32 = @floatFromInt(width);
    for (0..rows) |i| {
        const f_inverse_i: f32 = @floatFromInt(rows - (i + 1));
        const f_i: f32 = @floatFromInt(i);
        texture.drawPro(
            .{ .x = 0, .y = f_inverse_i * f_width, .width = f_width, .height = f_width },
            .{ .x = position.x, .y = position.y - f_i, .width = f_width, .height = f_width },
            .{ .x = f_width / 2, .y = f_width / 2 },
            std.math.radiansToDegrees(rotation),
            .white,
        );
    }
}

fn order_by_camera_position(camera: Camera, lhs: RenderRow, rhs: RenderRow) bool {
    const abs_position = lhs.transform.position;
    const lhs_relative_position = camera.get_relative_position(abs_position);

    const rhs_abs_position = rhs.transform.position;
    const rhs_relative_position = camera.get_relative_position(rhs_abs_position);

    return rhs_relative_position.y > lhs_relative_position.y;
}

const Light = struct {
    height: u8,
    radius: u8 = 120,
    color: rl.Color,
};

const LightRow = struct {
    entity: Entity,
    light: *Light,
    transform: *Transform,
};

const LightSystem = struct {
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

    pub fn draw_debug(self: Self, camera: Camera) void {
        discreete_render_texture.begin();
        for (self.arr.items) |light| {
            rl.drawCircleV(camera.get_relative_position(light.position), 8, light.color);
        }
        discreete_render_texture.end();
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        self.arr.clearAndFree(allocator);
    }
};

pub fn main() !void {
    rl.setTraceLogLevel(.warning);
    rl.initWindow(window_width, window_height, "test");
    defer rl.closeWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    try assets.init(allocator);
    defer assets.free(allocator);

    defer switch (gpa.deinit()) {
        .leak => std.log.err("memory leaks detected!", .{}),
        .ok => std.log.info("no memory leaks detected :)", .{}),
    };

    // debug rendering mode
    // could be typed as an enum but can't be bothered right now
    // 0 None
    // 1 Normal
    // 2 Height
    // 3 Discreet
    var debug_mode: i32 = 0;

    discreete_render_texture = try rl.loadRenderTexture(render_width, render_height);
    normal_render_texture = try rl.loadRenderTexture(render_width, render_height);
    height_render_texture = try rl.loadRenderTexture(render_width, render_height);

    const shader = try rl.loadShader(null, "shader.glsl");
    normal_shader = try rl.loadShader(null, "normal.glsl");
    height_shader = try rl.loadShader(null, "height.glsl");

    const relative_pos: rl.Vector2 = .{ .x = render_width / 2, .y = render_height / 2 };

    var camera: Camera = .init(render_width, render_height);
    camera.position = .init(100, 100);

    var ecs = ECS.init(allocator);
    defer ecs.free();
    defer ecs.debug();
    const item = ecs.create();
    _ = ecs.transforms.add(item, .{ .position = relative_pos });
    _ = ecs.ssprite.add(item, &assets.CAR_BASE);

    const item2 = ecs.create();
    _ = ecs.transforms.add(item2, .{ .position = relative_pos });
    _ = ecs.light.add(item2, .{ .color = .green, .height = 15 });

    var lights = LightSystem.init(allocator);
    defer lights.free(allocator);

    const lvl = try Level.init("dads", allocator, render_width, render_height);

    while (!rl.windowShouldClose()) {
        if (ecs.transforms.get(item2)) |t| {
            t.position = camera.get_absolute_position(rl.getMousePosition().divide(.init(4, 4)));
        }

        lvl.draw_normals(camera, normal_render_texture);
        lvl.draw(camera, discreete_render_texture);
        ecs.render(camera);

        if (rl.isKeyPressed(.n)) {
            debug_mode = @mod(1 + debug_mode, 4); // 4 is max debug modes
        }

        if (rl.isKeyPressed(.q)) {
            camera.rotation -= 0.1;
        }

        if (rl.isKeyPressed(.e)) {
            camera.rotation += 0.1;
        }

        // drawing final shader pass
        rl.beginDrawing();
        rl.clearBackground(.blank);

        shader.activate();
        lights.update_shader_values(camera, shader, &ecs);
        rl.setShaderValueTexture(shader, rl.getShaderLocation(shader, "normal"), normal_render_texture.texture);
        rl.setShaderValueTexture(shader, rl.getShaderLocation(shader, "height"), height_render_texture.texture);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "debug_mode"), &debug_mode, .int);
        rl.drawTexturePro(discreete_render_texture.texture, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(render_width),
            .height = @floatFromInt(-render_height),
        }, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(window_width),
            .height = @floatFromInt(window_height),
        }, rl.Vector2.zero(), 0, .white);
        shader.deactivate();

        // lvl.graphics_texture.drawV(.zero(), .white);
        // lvl.normal_texture.drawV(.zero(), .white);
        // drawing debug information
        rl.drawFPS(0, 0);
        switch (debug_mode) {
            1 => rl.drawText("normals", 0, 20, 50, .white),
            2 => rl.drawText("heights", 0, 20, 50, .white),
            3 => rl.drawText("discreet", 0, 20, 50, .white),
            else => {},
        }
        rl.endDrawing();

        // cleaning up render texture
        discreete_render_texture.begin();
        rl.clearBackground(.blank);
        discreete_render_texture.end();

        normal_render_texture.begin();
        rl.clearBackground(.blank);
        normal_render_texture.end();

        height_render_texture.begin();
        rl.clearBackground(.blank);
        height_render_texture.end();
    }
}
