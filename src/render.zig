const std = @import("std");
const rl = @import("raylib");
const Camera = @import("camera.zig").Camera;
const assets = @import("assets.zig");

const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;
const MAX_ENTITY_COUNT = consts.MAX_ENTITY_COUNT;

const window_width = consts.window_width;
const window_height = consts.window_height;

const _entity = @import("entity.zig");
const ECS = _entity.ECS;
const Entity = _entity.Entity;
const Transform = _entity.Transform;
const Particle = _entity.Particle;
const LightSystem = @import("light.zig").LightSystem;

const SparseSet = @import("entity.zig").SparseSet;

pub const RenderRow = struct {
    entity: Entity,
    transform: *Transform,
    sprite: assets.Assets,
    color: rl.Color = .white,
};

// Artifacts are occuring because the renderer batches up draw calls before
// entities are potentially destroyed, leaving some weird behaviour. But it's only visual because the drawing is naturally deferred until later.
// TODO Fix this shit
pub const RenderSystem = struct {
    camera: *Camera,
    discreete_render_texture: rl.RenderTexture,
    normal_render_texture: rl.RenderTexture,

    normal_shader: rl.Shader,
    final_shader: rl.Shader,

    render_rows: std.ArrayList(RenderRow),

    const SHADERS_PATH = "./assets/shaders/";
    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
        camera: *Camera,
    ) !Self {
        return .{
            .camera = camera,
            .discreete_render_texture = try rl.loadRenderTexture(render_width, render_height),
            .normal_render_texture = try rl.loadRenderTexture(render_width, render_height),
            .normal_shader = try rl.loadShader(null, SHADERS_PATH ++ "normal.glsl"),
            .render_rows = std.ArrayList(RenderRow).initCapacity(allocator, MAX_ENTITY_COUNT) catch unreachable,
            .final_shader = try rl.loadShader(null, SHADERS_PATH ++ "shader.glsl"),
        };
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        self.render_rows.clearAndFree(allocator);
    }

    fn stack_draw(texture: rl.Texture, rotation: f32, position: rl.Vector2, height: f32, color: rl.Color) void {
        const width = texture.width;
        const rows: usize = @intCast(@divTrunc(texture.height, width));
        const f_width: f32 = @floatFromInt(width);
        for (0..rows) |i| {
            const f_inverse_i: f32 = @floatFromInt(rows - (i + 1));
            const f_i: f32 = @floatFromInt(i);
            texture.drawPro(
                .{ .x = 0, .y = f_inverse_i * f_width, .width = f_width, .height = f_width },
                .{ .x = position.x, .y = position.y - f_i - height, .width = f_width, .height = f_width },
                .{ .x = f_width / 2, .y = f_width / 2 },
                std.math.radiansToDegrees(rotation),
                color,
            );
        }
    }

    fn query_render_rows(camera: Camera, transforms: *SparseSet(Transform), sprites: *SparseSet(assets.Assets), particles: *SparseSet(Particle), out: *std.ArrayList(RenderRow)) void {
        out.clearRetainingCapacity();
        for (sprites.dense_entities.items, 0..) |e, i| {
            if (transforms.get(e)) |t| {
                // TODO guarantee capacity
                const color: rl.Color = if (particles.get(e)) |p| p.color else .white;
                if (!camera.is_out_of_bounds(t.position)) out.appendAssumeCapacity(.{ .entity = e, .transform = t, .sprite = sprites.dense.items[i], .color = color });
            }
        }
    }

    pub fn draw(self: *Self) void {
        self.draw_system_function(self.render_rows.items);
    }

    pub fn update(ctx: *anyopaque, ecs: *ECS) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const camera = self.camera.*;
        query_render_rows(camera, &ecs.transforms, &ecs.ssprite, &ecs.particle, &self.render_rows);

        std.mem.sort(RenderRow, self.render_rows.items, camera, order_by_camera_position);
    }

    // this is much more performant than the previous implement
    // leaving it currently at 150fps @ 1000 entities
    // previous implementation had 60fps @ 1000 entities
    fn draw_system_function(self: Self, query: []RenderRow) void {
        const camera = self.camera.*;
        self.discreete_render_texture.begin();
        for (query) |q| stack_draw(
            assets.get(q.sprite).texture,
            q.transform.rotation - camera.rotation,
            camera.get_relative_position(q.transform.position),
            q.transform.height,
            q.color,
        );
        self.discreete_render_texture.end();

        self.normal_render_texture.begin();
        for (query) |q| {
            const position = camera.get_relative_position(q.transform.position);
            const rotation = q.transform.rotation - camera.rotation;
            const s = assets.get(q.sprite);
            self.normal_shader.activate();
            // passing in absolute 'rotation'
            // I think this is correct, it's world space rotation, it looks right!
            rl.setShaderValue(self.normal_shader, rl.getShaderLocation(self.normal_shader, "rotation"), &rotation, .float);
            stack_draw(s.normals, rotation, position, q.transform.height, .white);
            self.normal_shader.deactivate();
        }
        self.normal_render_texture.end();
    }

    pub fn clean(self: Self) void {
        // cleaning up render textures
        self.discreete_render_texture.begin();
        rl.clearBackground(.blank);
        self.discreete_render_texture.end();

        self.normal_render_texture.begin();
        rl.clearBackground(.blank);
        self.normal_render_texture.end();
    }

    // TODO move stuff out of here
    // this feels pretty bespoke and stupid
    pub fn draw_final_pass(self: Self, lights: *LightSystem, debug_mode: i32) void {
        const shader = self.final_shader;
        shader.activate();
        lights.update_shader_values(shader);
        rl.setShaderValueTexture(shader, rl.getShaderLocation(shader, "normal"), self.normal_render_texture.texture);
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "debug_mode"), &debug_mode, .int);
        rl.drawTexturePro(self.discreete_render_texture.texture, .{
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
    }
};

fn order_by_camera_position(camera: Camera, lhs: RenderRow, rhs: RenderRow) bool {
    const abs_position = lhs.transform.position;
    const lhs_relative_position = camera.get_relative_position(abs_position);

    const rhs_abs_position = rhs.transform.position;
    const rhs_relative_position = camera.get_relative_position(rhs_abs_position);

    return rhs_relative_position.y > lhs_relative_position.y;
}
