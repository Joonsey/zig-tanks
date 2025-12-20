const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

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

pub const Transform = extern struct {
    position: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
};

// this is much more performant than the previous implement
// leaving it currently at 150fps @ 1000 entities
// previous implementation had 60fps @ 1000 entities
fn draw_system_function(camera: Camera, query: []RenderRow) void {
    discreete_render_texture.begin();
    for (query) |q| stack_draw(assets.get(q.sprite).texture, q.transform.rotation - camera.rotation, camera.get_relative_position(q.transform.position));
    discreete_render_texture.end();

    normal_render_texture.begin();
    for (query) |q| {
        const position = camera.get_relative_position(q.transform.position);
        const rotation = q.transform.rotation - camera.rotation;
        const s = assets.get(q.sprite);
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
    sprite: assets.Assets,
};

const ECS = struct {
    transforms: SparseSet(Transform),
    ssprite: SparseSet(assets.Assets),
    light: SparseSet(Light),
    collider: SparseSet(Collider),

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
            .collider = .init(allocator, MAX_ENTITY_COUNT),

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

    fn query_render_rows(camera: Camera, transforms: *SparseSet(Transform), sprites: *SparseSet(assets.Assets), out: *std.ArrayList(RenderRow)) void {
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
        self.collider.deinit(self.allocator);

        self.render_rows.clearAndFree(self.allocator);
        self.free_entities.clearAndFree(self.allocator);
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

// Collisions are always around the center position of the object
// i am opting to do this because we don't need the 'position' from raylib
// aditionaly they need to be fine-tuned as they need to be rotated and i don't think a simple AABB
// rotation will suffice for rectangular collisions.
// in the instance for Rectangle, the X and Y are in radius, not diameter. Along each axis.
const Collider = union(enum) {
    Circle: f32,
    Rectangle: rl.Vector2,
};

const EditorUI = struct {
    selected_entity: ?Entity = null,
    last_added: ?Entity = null,
};

fn draw_ui(ui: *EditorUI, ecs: *ECS) void {
    const width = 120;
    var i: f32 = 22;
    if (ui.selected_entity) |e| {
        // transform
        if (ecs.transforms.get(e)) |t| {
            _ = rg.label(.init(20, i, width, 20), "Transform");
            i += 22;
            _ = rg.slider(.init(20, i, width, 20), "", "X", &t.position.x, 0, 600);
            i += 22;
            _ = rg.slider(.init(20, i, width, 20), "", "Y", &t.position.y, 0, 600);
            i += 22;
            _ = rg.slider(.init(20, i, width, 20), "", "Rotation", &t.rotation, 0, std.math.pi * 2);
            i += 22;
        }
        // sprite
        if (ecs.ssprite.get(e)) |s| {
            _ = rg.label(.init(20, i, width, 20), "Sprite");
            i += 22;
            var buff: [64]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buff, "Asset: {}", .{s.*}) catch "";
            var sv: f32 = @floatFromInt(@intFromEnum(s.*));
            _ = rg.slider(.init(20, i, width, 20), "", text, &sv, 0, @typeInfo(assets.Assets).@"enum".fields.len - 1);
            s.* = @enumFromInt(@as(u32, @intFromFloat(sv)));
            i += 22;
        }
        // light
        if (ecs.light.get(e)) |l| {
            _ = rg.label(.init(20, i, width, 20), "Lighting");
            i += 22;
            _ = rg.colorPicker(.init(20, i, width, 40), "", &l.color);
            i += 42;
            var h: f32 = @floatFromInt(l.height);
            _ = rg.slider(.init(20, i, width, 20), "", "Height", &h, 0, 200);
            l.height = @intFromFloat(h);
            i += 22;

            var r: f32 = @floatFromInt(l.radius);
            _ = rg.slider(.init(20, i, width, 20), "", "Radius", &r, 0, 255);
            l.radius = @intFromFloat(r);
            i += 22;

            if (rg.button(.init(20, i, width, 20), "Delete Light")) ecs.light.remove(e);
            i += 22;
        } else {
            if (rg.button(.init(20, i, width, 20), "Add Light")) _ = ecs.light.add(e, .{ .color = .white, .height = 0 });
            i += 22;
        }
        // collider
        if (ecs.collider.get(e)) |c| {
            _ = rg.label(.init(20, i, width, 20), "Collider");
            i += 22;
            switch (c.*) {
                .Circle => {
                    _ = rg.slider(.init(20, i, width, 20), "", "Radius", &c.Circle, 0, 255);
                    i += 22;
                },
                .Rectangle => |*r| {
                    _ = rg.slider(.init(20, i, width, 20), "", "X (radius)", &r.x, 0, 32);
                    i += 22;
                    _ = rg.slider(.init(20, i, width, 20), "", "Y (radius)", &r.y, 0, 32);
                    i += 22;
                },
            }
            if (rg.button(.init(20, i, width, 20), "Delete Collider")) ecs.collider.remove(e);
            i += 22;
        } else {
            if (rg.button(.init(20, i, width, 20), "Add Collider")) _ = ecs.collider.add(e, .{ .Rectangle = .init(8, 8) });
            i += 22;
        }
    }

    const num_renderables = ecs.render_rows.items.len;
    var buff: [64]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buff, "# renderables: {d}", .{num_renderables}) catch "";
    _ = rg.label(.init(20, i, width, 20), text);
    i += 22;
}

fn handle_input(camera: *Camera, dt: f32) void {
    const forward: rl.Vector2 = .{
        .x = @cos(camera.rotation),
        .y = @sin(camera.rotation),
    };

    const right: rl.Vector2 = .{
        .x = @cos(camera.rotation + std.math.pi * 0.5),
        .y = @sin(camera.rotation + std.math.pi * 0.5),
    };

    const accel = 600;
    var position = camera.position;
    if (rl.isKeyDown(.d)) {
        position.x += accel * forward.x * dt;
        position.y += accel * forward.y * dt;
    }
    if (rl.isKeyDown(.a)) {
        position.x -= accel * forward.x * dt;
        position.y -= accel * forward.y * dt;
    }
    if (rl.isKeyDown(.s)) {
        position.x += accel * right.x * dt;
        position.y += accel * right.y * dt;
    }
    if (rl.isKeyDown(.w)) {
        position.x -= accel * right.x * dt;
        position.y -= accel * right.y * dt;
    }

    if (rl.isKeyDown(.q)) {
        camera.rotation -= 3 * dt;
    }
    if (rl.isKeyDown(.e)) {
        camera.rotation += 3 * dt;
    }

    camera.target(position);
}

const MAGIC = 0x4C564C88;
pub fn save(path: []const u8, ecs: *ECS) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buffer: [1024]u8 = std.mem.zeroes([1024]u8);
    var writer = std.io.Writer.fixed(&buffer);

    try writer.writeInt(u8, 1, .little);
    try writer.writeInt(u32, MAGIC, .little);

    const entities = ecs.transforms.dense_entities.items;

    try writer.writeInt(u32, @intCast(entities.len), .little);
    for (entities) |e| {
        if (ecs.transforms.get(e)) |t| {
            try writer.writeInt(u8, 1, .little);
            try writer.writeStruct(t.*, .little);
        }
        if (ecs.ssprite.get(e)) |s| {
            try writer.writeInt(u8, 2, .little);
            try writer.writeInt(u32, @intFromEnum(s.*), .little);
        }
        if (ecs.light.get(e)) |l| {
            try writer.writeInt(u8, 3, .little);
            try writer.writeStruct(l.*, .little);
        }
        if (ecs.collider.get(e)) |c| {
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

pub fn load(path: []const u8, ecs: *ECS) !void {
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
        const e = ecs.create();
        var component = try reader.takeInt(u8, .little);
        while (component > 0) {
            switch (component) {
                // transform
                1 => _ = ecs.transforms.add(e, try reader.takeStruct(Transform, .little)),
                // ssprite
                2 => {
                    const s = try reader.takeInt(u32, .little);
                    _ = ecs.ssprite.add(e, @enumFromInt(s));
                },
                // light
                3 => _ = ecs.light.add(e, try reader.takeStruct(Light, .little)),
                4 => {
                    const r = try reader.takeInt(u8, .little);
                    switch (r) {
                        1 => _ = ecs.collider.add(e, .{ .Circle = @bitCast(try reader.takeInt(u32, .little)) }),
                        2 => _ = ecs.collider.add(e, .{ .Rectangle = try reader.takeStruct(rl.Vector2, .little) }),
                        else => std.log.warn("got unexpected collider id {d}", .{r}),
                    }
                },
                else => std.log.warn("got unexpected component id {d}", .{component}),
            }
            component = try reader.takeInt(u8, .little);
        }
    }
}

pub fn main() !void {
    rl.setTraceLogLevel(.warning);
    rl.initWindow(window_width, window_height, "test");
    defer rl.closeWindow();

    rg.loadStyle("style_dark.rgs");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer switch (gpa.deinit()) {
        .leak => std.log.err("memory leaks detected!", .{}),
        .ok => std.log.info("no memory leaks detected :)", .{}),
    };

    try assets.init(allocator);
    defer assets.free(allocator);

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

    var camera: Camera = .init(render_width, render_height);
    camera.position = .init(100, 100);

    var ecs = ECS.init(allocator);
    defer ecs.free();
    defer ecs.debug();

    var lights = LightSystem.init(allocator);
    defer lights.free(allocator);

    const lvl = try Level.init("dads", allocator, render_width, render_height);

    var eui: EditorUI = .{};
    try load("level", &ecs);

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        lvl.draw_normals(camera, normal_render_texture);
        lvl.draw(camera, discreete_render_texture);
        ecs.render(camera);

        if (rl.isKeyPressed(.n)) {
            debug_mode = @mod(1 + debug_mode, 4); // 4 is max debug modes
        }

        if (rl.isKeyDown(.q)) eui.selected_entity = null;

        handle_input(&camera, dt);

        if (rl.isMouseButtonPressed(.left)) {
            for (ecs.transforms.dense_entities.items) |e| if (ecs.transforms.get(e)) |t| {
                const mouse_position = rl.getMousePosition().divide(.init(4, 4));
                const relative_mouse_position = camera.get_absolute_position(mouse_position);
                if (relative_mouse_position.distance(t.position) < 8) {
                    eui.selected_entity = e;
                    break;
                }
            };
        }

        if (rl.isMouseButtonPressed(.right)) {
            for (ecs.transforms.dense_entities.items) |e| if (ecs.transforms.get(e)) |t| {
                const mouse_position = rl.getMousePosition().divide(.init(4, 4));
                const relative_mouse_position = camera.get_absolute_position(mouse_position);
                if (relative_mouse_position.distance(t.position) < 8) {
                    eui.selected_entity = ecs.copy(e);
                    break;
                }
            };
        }

        if (rl.isMouseButtonDown(.right) or rl.isMouseButtonDown(.left)) {
            const mouse_position = rl.getMousePosition().divide(.init(4, 4));
            const abs_mouse_position = camera.get_absolute_position(mouse_position);

            const mouse_move = ((rl.getMouseDelta().length() > 0) or rl.isKeyPressed(.w) or rl.isKeyPressed(.a) or rl.isKeyPressed(.s) or rl.isKeyPressed(.d));
            if (eui.selected_entity) |e| {
                if (ecs.transforms.get(e)) |t| {
                    if (abs_mouse_position.distance(t.position) < 16 and mouse_move) {
                        var anticipated_position = abs_mouse_position;
                        if (rl.isKeyDown(.left_alt)) {
                            for (0..ecs.transforms.dense_entities.items.len) |other_entity_index| {
                                // we iterate in reverse, just so that we are more likely to hit an element we recently introduced.
                                // It might be unneccessary but at least it feels really quite comfy and it doesn't seem to be fighting over edges
                                const other_entity = ecs.transforms.dense_entities.items[ecs.transforms.dense_entities.items.len - (other_entity_index + 1)];
                                if (ecs.transforms.get(other_entity)) |other| {
                                    if (other == t) continue;
                                    if (other.position.distance(t.position) > 22) continue;
                                    const delta_y = @abs(other.position.y - abs_mouse_position.y);
                                    const delta_x = @abs(other.position.x - abs_mouse_position.x);
                                    const y_aligned = delta_y < delta_x;
                                    if (y_aligned) anticipated_position.y = @floor(other.position.y) else anticipated_position.x = @floor(other.position.x);

                                    const pixel_perfect = if (ecs.collider.get(other_entity)) |c| switch (c.*) {
                                        .Circle => |r| if (y_aligned) @floor(delta_x) == @floor(r * 2) else @floor(delta_y) == @floor(r * 2),
                                        .Rectangle => |r| if (y_aligned) @floor(delta_x) == @floor(r.x * 2) else @floor(delta_y) == @floor(r.y * 2),
                                    } else false;

                                    if (pixel_perfect) {
                                        if (eui.last_added) |le| if (ecs.transforms.get(le)) |last_transform| if (last_transform.position.distance(t.position) < 8) break;
                                        if (rl.isMouseButtonDown(.left)) eui.selected_entity = null;
                                        if (rl.isMouseButtonDown(.right)) {
                                            eui.last_added = ecs.copy(e);
                                        }
                                    }
                                }
                            }
                        }
                        t.position = anticipated_position;
                    }
                }
            }
        }

        if (eui.selected_entity) |e| {
            if (ecs.transforms.get(e)) |t| {
                const mouse_wheel_move = rl.getMouseWheelMove() * std.math.pi * 360;
                t.rotation = @mod(t.rotation + mouse_wheel_move * dt, std.math.pi * 2);
            }
        }

        if (rl.isKeyPressed(.delete)) {
            if (eui.selected_entity) |e| ecs.destroy(e);
            eui.selected_entity = null;
        }

        if (rl.isKeyPressed(.s) and rl.isKeyDown(.left_control)) _ = try save("level", &ecs);

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

        // drawing debug information
        rl.drawFPS(0, 0);
        switch (debug_mode) {
            1 => rl.drawText("normals", 0, 20, 50, .white),
            2 => rl.drawText("heights", 0, 20, 50, .white),
            3 => rl.drawText("discreet", 0, 20, 50, .white),
            else => {},
        }
        draw_ui(&eui, &ecs);
        rl.endDrawing();

        // cleaning up render textures
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
