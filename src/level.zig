const std = @import("std");
const rl = @import("raylib");

const assets = @import("assets.zig");
const Camera = @import("camera.zig").Camera;

const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;

pub const Level = struct {
    physics_image: rl.Image,
    graphics_texture: rl.Texture,
    normal_texture: rl.Texture,
    intermediate_texture: rl.RenderTexture,
    shader: rl.Shader,

    const Self = @This();
    pub fn init(comptime path: []const u8, allocator: std.mem.Allocator) !Self {
        // TODO
        // redo this path shit
        // it should route a directory i think instead
        // also this is deifnetly wrong, the physics_image should not be the source for the normal map. I think
        const physics_image = rl.loadImage(path ++ ".png") catch unreachable;
        return .{
            .physics_image = physics_image,
            .graphics_texture = rl.loadTexture(path ++ ".png") catch unreachable,
            .intermediate_texture = rl.loadRenderTexture(render_width, render_height) catch unreachable,
            .normal_texture = create_normal(physics_image, allocator),
            .shader = try rl.loadShader(null, "world_water.glsl"),
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
                    normals[dst + 3] = 200; // luminocity
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
            .{ .x = 0, .y = 0, .width = f_width, .height = -f_height },
            .{ .x = relative_pos.x, .y = relative_pos.y, .width = f_width, .height = f_height },
            .{ .x = 0, .y = 0 },
            std.math.radiansToDegrees(-camera.rotation),
            .white,
        );
        normal_render_texture.end();
        rl.endBlendMode();
    }

    pub fn draw(self: Self, camera: Camera, discreete_render_texture: rl.RenderTexture) void {
        const shader = self.shader;
        const texture = self.graphics_texture;

        const relative_pos = camera.get_relative_position(.zero());
        const f_width: f32 = @floatFromInt(texture.width);
        const f_height: f32 = @floatFromInt(texture.height);
        self.intermediate_texture.begin();
        rl.clearBackground(.blank);
        texture.drawPro(
            .{ .x = 0, .y = 0, .width = f_width, .height = -f_height },
            .{ .x = relative_pos.x, .y = relative_pos.y, .width = f_width, .height = f_height },
            .{ .x = 0, .y = 0 },
            std.math.radiansToDegrees(-camera.rotation),
            .white,
        );
        self.intermediate_texture.end();

        discreete_render_texture.begin();
        shader.activate();
        const i_texture = self.intermediate_texture.texture;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_tex_width"), &i_texture.width, .int);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_tex_height"), &i_texture.height, .int);

        const camera_rotation = camera.rotation;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_rotation"), &camera_rotation, .float);
        const camera_position_x: f32 = camera.position.x;
        const camera_position_y: f32 = camera.position.y;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_offset_x"), &camera_position_x, .float);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_offset_y"), &camera_position_y, .float);

        const camera_screen_offset_x = camera.render_dimensions.x - camera.screen_offset.x;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_screen_offset_x"), &camera_screen_offset_x, .float);
        const camera_screen_offset_y = camera.render_dimensions.y - camera.screen_offset.y;
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_camera_screen_offset_y"), &camera_screen_offset_y, .float);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "u_time"), &@as(f32, @floatCast(rl.getTime())), .float);

        const if_width: f32 = @floatFromInt(i_texture.width);
        const if_height: f32 = @floatFromInt(i_texture.height);
        self.intermediate_texture.texture.drawPro(
            .{ .x = 0, .y = 0, .width = if_width, .height = -if_height },
            .{ .x = 0, .y = 0, .width = if_width, .height = if_height },
            .zero(),
            0,
            .white,
        );
        shader.deactivate();
        discreete_render_texture.end();
    }
};

pub const Levels = enum(u32) { DEMO };

pub var levels: std.EnumArray(Levels, Level) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    levels.set(.DEMO, try .init("graphics", allocator));
}

pub fn free(allocator: std.mem.Allocator) void {
    _ = allocator;
}

pub fn get(l: Levels) *Level {
    return levels.getPtr(l);
}
