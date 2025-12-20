const std = @import("std");
const rl = @import("raylib");

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

pub const SSprite = struct {
    texture: rl.Texture,
    normals: rl.Texture,

    const Self = @This();
    fn init(path: [:0]const u8, allocator: std.mem.Allocator) !Self {
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

pub const Assets = enum(u32) {
    CAR_BASE,
    FENCE_0,
    ITEMBOX,
    LAMP,
};

var assets: std.ArrayList(SSprite) = .{};

pub fn init(allocator: std.mem.Allocator) !void {
    try assets.append(allocator, try .init("car_base.png", allocator));
    try assets.append(allocator, try .init("fence-0.png", allocator));
    try assets.append(allocator, try .init("itembox.png", allocator));
    try assets.append(allocator, try .init("lamp.png", allocator));
}

pub fn free(allocator: std.mem.Allocator) void {
    assets.clearAndFree(allocator);
}

pub fn get(a: Assets) *SSprite {
    return &assets.items[@intFromEnum(a)];
}
