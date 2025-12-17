const std = @import("std");
const rl = @import("raylib");
const window_height = 720;
const window_width = 1080;

var discreete_render_texture: rl.RenderTexture = undefined;
var normal_render_texture: rl.RenderTexture = undefined;
var height_render_texture: rl.RenderTexture = undefined;

var normal_shader: rl.Shader = undefined;
var height_shader: rl.Shader = undefined;

pub const SSprite = struct {
    texture: rl.Texture,
    normals: rl.Texture,
    rotation: f32 = 0,
    position: rl.Vector2 = .{ .x = 0, .y = 0 },

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

    pub fn draw(self: Self) void {
        discreete_render_texture.begin();
        stack_draw(self.texture, self.rotation, self.position);
        discreete_render_texture.end();

        normal_render_texture.begin();
        normal_shader.activate();
        rl.setShaderValue(normal_shader, rl.getShaderLocation(normal_shader, "rotation"), &self.rotation, .float);
        stack_draw(self.normals, self.rotation, self.position);
        normal_shader.deactivate();
        normal_render_texture.end();

        // eats up performance, disabling for now
        //height_render_texture.begin();
        //// drawing manually because we need to embedd shader information
        //const width = self.texture.width;
        //const rows: usize = @intCast(@divTrunc(self.texture.height, width));
        //const f_width: f32 = @floatFromInt(width);
        //for (0..rows) |i| {
        //    const f_inverse_i: f32 = @floatFromInt(rows - (i + 1));
        //    const f_i: f32 = @floatFromInt(i);
        //    // need to activate and deactivate to disabling batching
        //    // causing the 'height' to be shadowed and equal to the latest value
        //    height_shader.activate();
        //    rl.setShaderValue(height_shader, rl.getShaderLocation(height_shader, "height"), &(f_i), .float);
        //    self.texture.drawPro(
        //        .{ .x = 0, .y = f_inverse_i * f_width, .width = f_width, .height = f_width },
        //        .{ .x = self.position.x, .y = self.position.y - f_i, .width = f_width, .height = f_width },
        //        .{ .x = f_width / 2, .y = f_width / 2 },
        //        std.math.radiansToDegrees(self.rotation),
        //        .white,
        //    );
        //    height_shader.deactivate();
        //}
        //height_render_texture.end();
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

pub fn main() !void {
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

    discreete_render_texture = try rl.loadRenderTexture(window_width / 4, window_height / 4);
    normal_render_texture = try rl.loadRenderTexture(window_width / 4, window_height / 4);
    height_render_texture = try rl.loadRenderTexture(window_width / 4, window_height / 4);

    const shader = try rl.loadShader(null, "shader.glsl");
    normal_shader = try rl.loadShader(null, "normal.glsl");
    height_shader = try rl.loadShader(null, "height.glsl");

    var sprite = try SSprite.init("car_base.png", allocator);

    const relative_pos: rl.Vector2 = .{ .x = window_width / 8, .y = window_height / 8 };
    sprite.position = relative_pos;

    var light_height: f32 = 15.0 / 255.0;

    while (!rl.windowShouldClose()) {
        sprite.rotation = @floatCast(rl.getTime());
        sprite.position = relative_pos;

        for (0..10) |x| {
            sprite.position.x = @floatFromInt(x * 40);
            sprite.draw();
        }

        // debug buttons
        if (rl.isMouseButtonPressed(.left)) {
            light_height += (1.0 / 255.0);
            std.log.debug("light_height: {d:.0}", .{light_height * 255.0});
        }
        if (rl.isMouseButtonPressed(.right)) {
            light_height -= (1.0 / 255.0);
            std.log.debug("light_height: {d:.0}", .{light_height * 255.0});
        }

        if (rl.isKeyPressed(.n)) {
            debug_mode = @mod(1 + debug_mode, 4); // 4 is max debug modes
        }

        const mouse = rl.getMousePosition().divide(.{ .x = window_width, .y = window_height });

        // drawing final shader pass
        rl.beginDrawing();
        rl.clearBackground(.blank);
        shader.activate();
        rl.setShaderValueTexture(shader, rl.getShaderLocation(shader, "normal"), normal_render_texture.texture);
        rl.setShaderValueTexture(shader, rl.getShaderLocation(shader, "height"), height_render_texture.texture);
        rl.setShaderValueV(shader, rl.getShaderLocation(shader, "mouse"), &mouse, .vec2, 1);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "debug_mode"), &debug_mode, .int);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "light_height"), &light_height, .float);
        rl.drawTexturePro(discreete_render_texture.texture, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(window_width / 4),
            .height = @floatFromInt(-window_height / 4),
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
