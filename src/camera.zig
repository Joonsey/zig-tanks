const std = @import("std");
const rl = @import("raylib");

const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;

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
