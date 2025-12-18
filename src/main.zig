const std = @import("std");
const rl = @import("raylib");
const window_height = 720;
const window_width = 1080;

const render_height = window_height / 4;
const render_width = window_width / 4;

var discreete_render_texture: rl.RenderTexture = undefined;
var normal_render_texture: rl.RenderTexture = undefined;
var height_render_texture: rl.RenderTexture = undefined;

var normal_shader: rl.Shader = undefined;
var height_shader: rl.Shader = undefined;

pub const Camera = struct {
    position: rl.Vector2,
    screen_offset: rl.Vector2,
    render_dimensions: rl.Vector2,
    rotation: f32,

    const Self = @This();
    pub fn init() Self {
        return .{
            .position = .{ .x = 0, .y = 0 },
            .screen_offset = .{ .x = render_width / 2, .y = render_height * 0.8 },
            .render_dimensions = .{ .x = render_width, .y = render_height },
            .rotation = 0,
        };
    }

    pub fn target(self: *Self, target_pos: rl.Vector2) void {
        const coefficient = 10.0;
        self.position.x += (target_pos.x - self.position.x) / coefficient;
        self.position.y += (target_pos.y - self.position.y) / coefficient;
    }

    pub fn get_relative_position(self: Self, abs_position: rl.Vector2) rl.Vector2 {
        const delta = abs_position.subtract(self.position);
        const cos_r = @cos(-self.rotation);
        const sin_r = @sin(-self.rotation);

        const rotated: rl.Vector2 = .{
            .x = delta.x * cos_r - delta.y * sin_r,
            .y = delta.x * sin_r + delta.y * cos_r,
        };

        return rotated.add(self.screen_offset);
    }

    pub fn get_absolute_position(self: Self, relative_position: rl.Vector2) rl.Vector2 {
        const delta = relative_position.subtract(self.screen_offset);
        const cos_r = @cos(self.rotation);
        const sin_r = @sin(self.rotation);

        const rotated: rl.Vector2 = .{
            .x = delta.x * cos_r - delta.y * sin_r,
            .y = delta.x * sin_r + delta.y * cos_r,
        };

        return self.position.add(rotated);
    }

    pub fn is_out_of_bounds(self: Self, abs_position: rl.Vector2) bool {
        const relative_pos = self.get_relative_position(abs_position);

        const render_box = rl.Rectangle.init(0, 0, self.render_dimensions.x, self.render_dimensions.y);

        const generosity = 100;
        const arg_box = rl.Rectangle.init(relative_pos.x - generosity, relative_pos.y - generosity, generosity * 2, generosity * 2);

        return !render_box.checkCollision(arg_box);
    }
};

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

pub const SSprite = struct {
    texture: rl.Texture,
    normals: rl.Texture,

    const Self = @This();
    pub fn init(path: [:0]const u8, allocator: std.mem.Allocator) !Self {
        const texture = try rl.loadTexture(path);
        const density = try build_density_volume(texture, allocator);
        defer allocator.free(density);

        const w: usize = @intCast(texture.width);
        const d: usize = @intCast(@divTrunc(texture.height, texture.width));
        const gradients = try build_gradient_volume(density, w, d, allocator);
        defer allocator.free(gradients);

        const atlas = try build_gradient_atlas(gradients, w, d, allocator);
        defer allocator.free(atlas);

        const normals = try build_normal_atlas(atlas, w, d);

        return .{ .normals = normals, .texture = texture };
    }
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

const MAX_ENTITY_COUNT = 10000;

const RenderRow = struct {
    entity: Entity,
    transform: *Transform,
    sprite: *SSprite,
};

const ECS = struct {
    transforms: SparseSet(Transform),
    ssprite: SparseSet(*SSprite),

    render_rows: std.ArrayList(RenderRow),

    next: Entity = 0,
    free_entities: std.ArrayList(Entity),

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .transforms = .init(allocator, MAX_ENTITY_COUNT),
            .ssprite = .init(allocator, MAX_ENTITY_COUNT),

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

        self.transforms.remove(e);
        self.ssprite.remove(e);
    }

    fn query_render_rows(camera: Camera, transforms: *SparseSet(Transform), sprites: *SparseSet(*SSprite), out: *std.ArrayList(RenderRow)) void {
        out.clearRetainingCapacity();

        for (sprites.dense_entities.items, 0..) |e, i| {
            if (transforms.get(e)) |t| {
                // TODO guarantee capacity
                if (!camera.is_out_of_bounds(t.position)) out.appendAssumeCapacity(.{ .entity = e, .transform = t, .sprite = sprites.dense.items[i] });
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

        self.render_rows.clearAndFree(self.allocator);
        self.free_entities.clearAndFree(self.allocator);
    }

    pub fn debug(self: *Self) void {
        std.log.debug("ECS DEBUG START", .{});
        for (0..self.next) |ue| {
            const e: Entity = @intCast(ue);
            std.log.debug("{?} | {?*}", .{
                self.transforms.get(e),
                if (self.ssprite.get(e)) |s| s.* else null,
            });
        }
        std.log.debug("number of renderables last frame: {d}", .{self.render_rows.items.len});
    }
};

fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const nx = std.math.clamp((x - edge0) / (edge1 - edge0), 0, 1);

    return nx * nx * (3.0 - 2.0 * nx);
}

fn build_density_volume(
    texture: rl.Texture,
    allocator: std.mem.Allocator,
) ![]f32 {
    const slice_size: usize = @intCast(texture.width);
    const slice_count: usize = @intCast(@divTrunc(texture.height, texture.width));
    const slice_area = slice_size * slice_size;

    var density = try allocator.alloc(f32, slice_count * slice_area);

    var image = try rl.loadImageFromTexture(texture);
    defer image.unload();

    for (0..slice_count) |z| {
        const src_y_base = z * slice_size;

        for (0..slice_size) |y| {
            for (0..slice_size) |x| {
                const src_x = x;
                const src_y = src_y_base + y;

                const color = image.getColor(@intCast(src_x), @intCast(src_y));
                const alpha: f32 = @floatFromInt(color.a);

                const dst_index = z * slice_area + y * slice_size + x;
                // smoothstep?
                density[dst_index] = smoothstep(0.1, 0.9, alpha / 255);
            }
        }
    }

    return density;
}

fn sample_density(
    density: []const f32,
    w: usize,
    d: usize,
    x: i32,
    y: i32,
    z: i32,
) f32 {
    const ix = std.math.clamp(x, 0, w - 1);
    const iy = std.math.clamp(y, 0, w - 1);
    const iz = std.math.clamp(z, 0, d - 1);

    return density[iz * w * w + iy * w + ix];
}

fn compute_gradient(
    density: []const f32,
    w: usize,
    d: usize,
    x: i32,
    y: i32,
    z: i32,
) [3]f32 {
    const dx =
        sample_density(density, w, d, x + 1, y, z) -
        sample_density(density, w, d, x - 1, y, z);

    const dy =
        sample_density(density, w, d, x, y + 1, z) -
        sample_density(density, w, d, x, y - 1, z);

    const dz =
        sample_density(density, w, d, x, y, z + 1) -
        sample_density(density, w, d, x, y, z - 1);

    return .{ dx, dy, dz };
}

fn build_gradient_volume(
    density: []const f32,
    w: usize,
    d: usize,
    allocator: std.mem.Allocator,
) ![]f32 {
    const voxel_count = w * w * d;
    var gradients = try allocator.alloc(f32, voxel_count * 3);

    for (0..d) |z| {
        for (0..w) |y| {
            for (0..w) |x| {
                const idx = z * w * w + y * w + x;
                const g = compute_gradient(density, w, d, @intCast(x), @intCast(y), @intCast(z));
                const wgt = smoothstep(0.05, 0.25, density[idx]);

                gradients[idx * 3 + 0] = g[0] * wgt;
                gradients[idx * 3 + 1] = g[1] * wgt;
                gradients[idx * 3 + 2] = g[2] * wgt;
            }
        }
    }

    return gradients;
}

fn build_gradient_atlas(
    gradients: []const f32,
    w: usize,
    d: usize,
    allocator: std.mem.Allocator,
) ![]u8 {
    const atlas_width = w;
    const atlas_height = w * d;

    var atlas = try allocator.alloc(u8, atlas_width * atlas_height * 4);

    for (0..d) |z| {
        for (0..w) |y| {
            for (0..w) |x| {
                const src = (z * w * w + y * w + x) * 3;

                const dst = ((z * w + y) * w + x) * 4;

                var alpha: u8 = 0;
                for (0..3) |c| {
                    const v = std.math.clamp(gradients[src + c] * 0.5 + 0.5, 0.0, 1.0);
                    atlas[dst + c] = @intFromFloat(v * 255);

                    if (gradients[src + c] != 0) alpha = 255;
                }
                atlas[dst + 3] = alpha;
            }
        }
    }

    return atlas;
}

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

fn build_normal_atlas(atlas: []u8, slice_size: usize, slice_count: usize) !rl.Texture {
    const image = rl.Image{
        .data = @ptrCast(atlas.ptr),
        .width = @intCast(slice_size),
        .height = @intCast(slice_size * slice_count),
        .mipmaps = 1,
        .format = .uncompressed_r8g8b8a8,
    };

    const gradient_texture = try rl.loadTextureFromImage(image);
    rl.setTextureFilter(gradient_texture, .point);
    return gradient_texture;
}

fn order_by_camera_position(camera: Camera, lhs: RenderRow, rhs: RenderRow) bool {
    const abs_position = lhs.transform.position;
    const lhs_relative_position = camera.get_relative_position(abs_position);

    const rhs_abs_position = rhs.transform.position;
    const rhs_relative_position = camera.get_relative_position(rhs_abs_position);

    return rhs_relative_position.y > lhs_relative_position.y;
}

const Light = struct {
    position: rl.Vector2,
    height: u8,
    radius: u8 = 50,
    color: rl.Color,
};

const Lights = struct {
    arr: std.ArrayList(Light),
    allocator: std.mem.Allocator,

    debug_i: u32 = 0,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator, .arr = .{} };
    }

    pub fn add(self: *Self, light: Light) void {
        self.arr.append(self.allocator, light) catch unreachable;

        // TOO MANY LIGHTS DO SOMETHING ABOUT IT AND REMOVE THIS
        // ONLY AFTER THIS HAS BEEN RESOLVED FOR
        if (self.arr.items.len >= 25) @panic("TOO MANY LIGHTS");
    }

    pub fn update(self: *Self, camera: Camera, shader: rl.Shader) void {
        var i: u32 = 0; // needs to be u32 because it's passed to the shader.
        // even though we can reason this could be a usize or u8
        for (self.arr.items) |light| {
            if (camera.is_out_of_bounds(light.position)) continue;

            rl.setShaderValue(shader, rl.getShaderLocation(shader, rl.textFormat("lights[%i].position", .{i})), &camera.get_relative_position(light.position).divide(.init(render_width, render_height)), .vec2);

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

            i += 1;
        }
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "light_count"), &i, .int);
        self.debug_i = i;
    }

    pub fn debug(self: Self) void {
        std.log.debug("LIGHTS DEBUG START", .{});
        std.log.debug("number of total lights: {d}, lights being rendered in scene: {d}", .{ self.arr.items.len, self.debug_i });
    }

    pub fn draw_debug(self: Self, camera: Camera) void {
        discreete_render_texture.begin();
        for (self.arr.items) |light| {
            std.log.debug("{}, {}", .{ camera.get_relative_position(light.position), light.position });
            rl.drawCircleV(camera.get_relative_position(light.position), 8, light.color);
        }
        discreete_render_texture.end();
    }

    pub fn free(self: *Self) void {
        self.arr.clearAndFree(self.allocator);
    }
};

pub fn main() !void {
    rl.setTraceLogLevel(.warning);
    rl.initWindow(window_width, window_height, "test");
    defer rl.closeWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

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

    var sprite = try SSprite.init("itembox.png", allocator);
    var sprite2 = try SSprite.init("car_base.png", allocator);

    const relative_pos: rl.Vector2 = .{ .x = render_width / 2, .y = render_height / 2 };

    var camera: Camera = .init();

    var ecs = ECS.init(allocator);
    defer ecs.free();
    defer ecs.debug();
    const item = ecs.create();
    _ = ecs.transforms.add(item, .{ .position = relative_pos });
    _ = ecs.ssprite.add(item, &sprite);

    const item2 = ecs.create();
    _ = ecs.transforms.add(item2, .{ .position = .zero() });
    _ = ecs.ssprite.add(item2, &sprite);

    for (0..2) |x| {
        const xi = ecs.create();
        _ = ecs.transforms.add(xi, .{ .position = relative_pos.subtract(.init(80, 0)).add(.init(@floatFromInt(x * 40), 0)) });
        _ = ecs.ssprite.add(xi, &sprite2);
    }

    ecs.destroy(2);

    var lights = Lights.init(allocator);
    defer lights.free();
    defer lights.debug();
    lights.add(.{ .color = .white, .height = 1, .position = .init(0, 0) });
    lights.add(.{ .color = .red, .height = 0, .position = .init(0, -100) });
    // lights.add(.{ .color = .green, .height = 45, .position = relative_pos.add(.init(-20, 0)) });
    // lights.add(.{ .color = .orange, .height = 45, .position = relative_pos.add(.init(-20, 100)) });
    lights.add(.{ .color = .green, .height = 15, .position = relative_pos.add(.init(200, 300)) });

    while (!rl.windowShouldClose()) {
        const rotation: f32 = @floatCast(rl.getTime());
        _ = rotation;
        if (ecs.transforms.get(item)) |_| {
            // t.rotation = rotation
            // t.position = camera.get_absolute_position(rl.getMousePosition().divide(.init(4, 4)));
        }

        lights.arr.items[0].position = camera.get_absolute_position(rl.getMousePosition().divide(.init(4, 4)));

        ecs.render(camera);

        // lights.draw_debug(camera);

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
        lights.update(camera, shader);
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
