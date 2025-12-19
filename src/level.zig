const std = @import("std");
const rl = @import("raylib");

const assets = @import("assets.zig");
const Camera = @import("camera.zig").Camera;

pub const Level = struct {
    physics_image: rl.Image,
    graphics_texture: rl.Texture,
    normal_texture: rl.Texture,
    intermediate_texture: rl.RenderTexture,

    const Self = @This();
    pub fn init(path: []const u8, allocator: std.mem.Allocator, render_width: i32, render_height: i32) !Self {
        _ = path;
        const physics_image = rl.loadImage("graphics.png") catch unreachable;
        return .{
            .physics_image = physics_image,
            .graphics_texture = rl.loadTexture("graphics.png") catch unreachable,
            .intermediate_texture = rl.loadRenderTexture(render_width, render_height) catch unreachable,
            .normal_texture = create_normal(physics_image, allocator),
        };
    }

    fn create_normal(image: rl.Image, allocator: std.mem.Allocator) rl.Texture {
        const normals = allocator.alloc(u8, @intCast(image.width * image.height * 4)) catch unreachable;
        defer allocator.free(normals);
        for (0..@intCast(image.height)) |y| {
            for (0..@intCast(image.width)) |x| {
                const src_x = x;
                const src_y = y;

                const color = image.getColor(@intCast(src_x), @intCast(src_y));
                const alpha: f32 = @floatFromInt(color.a);

                const dst = (src_y * @as(usize, @intCast(image.width)) + src_x) * 4;
                if (alpha >= 0.01 and color.r != 0 and color.g != 0 and color.b != 0) {
                    normals[dst + 0] = @intFromFloat(std.math.clamp(0 * 0.5 + 0.5, 0.0, 1.0) * 255);
                    normals[dst + 1] = @intFromFloat(std.math.clamp(0 * 0.5 + 0.5, 0.0, 1.0) * 255);
                    normals[dst + 2] = @intFromFloat(std.math.clamp(1 * 0.5 + 0.5, 0.0, 1.0) * 255);
                    normals[dst + 3] = 50; // luminocity
                } else {
                    normals[dst + 0] = 0;
                    normals[dst + 1] = 0;
                    normals[dst + 2] = 0;
                    normals[dst + 3] = 0;
                }
            }
        }

        const new_image = rl.Image{
            .data = @ptrCast(normals.ptr),
            .width = @intCast(image.width),
            .height = @intCast(image.height),
            .mipmaps = 1,
            .format = .uncompressed_r8g8b8a8,
        };

        const gradient_texture = rl.loadTextureFromImage(new_image) catch unreachable;
        rl.setTextureFilter(gradient_texture, .point);
        return gradient_texture;
    }

    pub fn draw_normals(self: Self, camera: Camera, normal_render_texture: rl.RenderTexture) void {
        rl.beginBlendMode(.custom);
        rl.gl.rlSetBlendFactors(1, 0, rl.gl.rl_func_add);
        normal_render_texture.begin();
        const relative_pos = camera.get_relative_position(.zero());

        const texture = self.normal_texture;
        const f_width: f32 = @floatFromInt(texture.width);
        const f_height: f32 = @floatFromInt(texture.height);
        texture.drawPro(
            .{ .x = 0, .y = 0, .width = f_width, .height = f_height },
            .{ .x = relative_pos.x, .y = relative_pos.y, .width = f_width, .height = f_height },
            .{ .x = 0, .y = 0 },
            std.math.radiansToDegrees(-camera.rotation),
            .white,
        );
        normal_render_texture.end();
        rl.endBlendMode();
    }

    pub fn draw(self: Self, camera: Camera, discreete_render_texture: rl.RenderTexture) void {
        discreete_render_texture.begin();
        const relative_pos = camera.get_relative_position(.zero());

        const texture = self.graphics_texture;
        const f_width: f32 = @floatFromInt(texture.width);
        const f_height: f32 = @floatFromInt(texture.height);
        texture.drawPro(
            .{ .x = 0, .y = 0, .width = f_width, .height = f_height },
            .{ .x = relative_pos.x, .y = relative_pos.y, .width = f_width, .height = f_height },
            .{ .x = 0, .y = 0 },
            std.math.radiansToDegrees(-camera.rotation),
            .white,
        );
        discreete_render_texture.end();
    }
};
