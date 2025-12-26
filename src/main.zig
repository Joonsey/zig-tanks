const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const assets = @import("assets.zig");
const levels = @import("level.zig");

const Camera = @import("camera.zig").Camera;
const Entity = @import("entity.zig").Entity;
const ECS = @import("entity.zig").ECS;

const LightSystem = @import("light.zig").LightSystem;
const RenderSystem = @import("render.zig").RenderSystem;
const PhysicsSystem = @import("physics.zig").PhysicsSystem;
const BulletSystem = @import("bullet.zig").BulletSystem;

const consts = @import("consts.zig");
const render_width = consts.render_width;
const render_height = consts.render_height;

const window_width = consts.window_width;
const window_height = consts.window_height;

const EditorUI = struct {
    selected_entity: ?Entity = null,
    last_added: ?Entity = null,
};

fn draw_ui(ui: *EditorUI, ecs: *ECS, renders: RenderSystem) void {
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
            switch (c.shape) {
                .Circle => |r| {
                    var buff: [64]u8 = undefined;
                    const text = std.fmt.bufPrintZ(&buff, "Radius: {d:.2}", .{r}) catch "";
                    _ = rg.slider(.init(20, i, width, 20), "", text, &c.shape.Circle, 0, 255);
                    i += 22;
                },
                .Rectangle => |*r| {
                    var buff: [64]u8 = undefined;
                    var text = std.fmt.bufPrintZ(&buff, "X (radius): {d:.2}", .{r.x}) catch "";
                    _ = rg.slider(.init(20, i, width, 20), "", text, &r.x, 0, 32);
                    i += 22;
                    text = std.fmt.bufPrintZ(&buff, "X (radius): {d:.2}", .{r.y}) catch "";
                    _ = rg.slider(.init(20, i, width, 20), "", text, &r.y, 0, 32);
                    i += 22;
                },
            }
            if (rg.button(.init(20, i, width, 20), "Delete Collider")) ecs.collider.remove(e);
            i += 22;
        } else {
            if (rg.button(.init(20, i, width, 20), "Add Collider")) _ = ecs.collider.add(e, .{ .shape = .{ .Rectangle = .init(8, 8) } });
            i += 22;
        }
        // rigidbody
        if (ecs.rigidbody.get(e)) |rb| {
            _ = rg.label(.init(20, i, width, 20), "Rigidbody");
            i += 22;
            if (rg.button(.init(20, i, width, 20), "Delete Rigidbody")) ecs.rigidbody.remove(e);
            i += 22;
            var buff: [64]u8 = undefined;
            var text = std.fmt.bufPrintZ(&buff, "damping: {d:.2}", .{rb.damping}) catch "";
            _ = rg.slider(.init(20, i, width, 20), "", text, &rb.damping, 0, 1);
            i += 22;
            text = std.fmt.bufPrintZ(&buff, "Inv Mass: {d:.2}", .{rb.inv_mass}) catch "";
            _ = rg.slider(.init(20, i, width, 20), "", text, &rb.inv_mass, 0, 10);
            i += 22;
        } else {
            if (rg.button(.init(20, i, width, 20), "Add Rigidbody")) _ = ecs.rigidbody.add(e, .{});
            i += 22;
        }
    }

    const num_renderables = renders.render_rows.items.len;
    var buff: [64]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buff, "# renderables: {d}", .{num_renderables}) catch "";
    _ = rg.label(.init(20, i, width, 20), text);
    i += 22;
}

pub fn main() !void {
    rl.setTraceLogLevel(.warning);
    rl.initWindow(window_width, window_height, "test");
    defer rl.closeWindow();

    rg.loadStyle("./assets/ui_style.rgs");

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
    var freecam: bool = true;

    var camera: Camera = .init();
    camera.position = .init(100, 100);

    var ecs = ECS.init(allocator);
    defer ecs.free();
    defer ecs.debug();

    var lights = LightSystem.init(allocator, &camera);
    defer lights.free(allocator);

    var renders = try RenderSystem.init(allocator, &camera);
    defer renders.free(allocator);

    var physics = PhysicsSystem.init(allocator);
    defer physics.free(allocator);

    var bullets = BulletSystem.init(allocator);
    defer bullets.free(allocator);

    ecs.add_system(.{ .ctx = &renders, .update_fn = &RenderSystem.update });
    ecs.add_system(.{ .ctx = &lights, .update_fn = &LightSystem.update });
    ecs.add_system(.{ .ctx = &physics, .update_fn = &PhysicsSystem.update });
    ecs.add_system(.{ .ctx = &bullets, .update_fn = &BulletSystem.update });

    ecs.add_event_listener(.{ .ctx = &bullets, .on_event_fn = &BulletSystem.on_event });

    try levels.init(allocator);
    defer levels.free(allocator);

    const lvl = levels.get(.DEMO);
    var eui: EditorUI = .{};
    lvl.seed_ecs(&ecs) catch {
        for (0..10) |i| {
            const entity = ecs.create();
            _ = ecs.transforms.add(entity, .{ .position = .init(@floatFromInt(i * 20), 100) });
            _ = ecs.ssprite.add(entity, .ITEMBOX);
            _ = ecs.rigidbody.add(entity, .{});
        }
    };

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        lvl.draw_normals(camera, renders.normal_render_texture);
        lvl.draw(camera, renders.discreete_render_texture);

        ecs.update();

        renders.draw();

        if (rl.isKeyPressed(.n)) {
            debug_mode = @mod(1 + debug_mode, 4); // 4 is max debug modes
        }

        if (rl.isKeyDown(.q)) eui.selected_entity = null;

        if (freecam) camera.handle_input(dt);
        if (!freecam) {
            if (ecs.transforms.get(0)) |t| {
                if (ecs.rigidbody.get(0)) |rb| {
                    const forward: rl.Vector2 = .{
                        .x = @cos(t.rotation),
                        .y = @sin(t.rotation),
                    };

                    const accel = 260;
                    const rotation_force = 1.5;
                    if (rl.isKeyDown(.w)) {
                        rb.velocity.x += accel * forward.x * dt;
                        rb.velocity.y += accel * forward.y * dt;
                    }
                    if (rl.isKeyDown(.s)) {
                        rb.velocity.x -= accel * forward.x * dt;
                        rb.velocity.y -= accel * forward.y * dt;
                    }

                    if (rl.isKeyDown(.a)) {
                        t.rotation -= rotation_force * dt;
                    }
                    if (rl.isKeyDown(.d)) {
                        t.rotation += rotation_force * dt;
                    }

                    var delta = t.rotation + std.math.pi * 0.5 - camera.rotation;
                    // simple angle wrapping, might be better way to this
                    delta = std.math.atan2(std.math.sin(delta), std.math.cos(delta));
                    camera.rotation += delta / 20;

                    camera.target(t.position);
                }
            }
        }

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

                                    const pixel_perfect = if (ecs.collider.get(other_entity)) |c| switch (c.shape) {
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

        if (rl.isKeyPressed(.s) and rl.isKeyDown(.left_control)) _ = try ecs.save(lvl.get_data_path());

        if (rl.isKeyPressed(.m)) freecam = !freecam;
        rl.beginDrawing();
        rl.clearBackground(.blank);

        if (rl.isKeyPressed(.o)) bullets.add(0, .{ .type = .Demo }, &ecs);

        renders.draw_final_pass(&lights, debug_mode);
        // drawing debug information
        rl.drawFPS(0, 0);
        switch (debug_mode) {
            1 => rl.drawText("normals", 0, 20, 50, .white),
            2 => {
                for (ecs.collider.dense_entities.items) |e| {
                    if (ecs.collider.get(e)) |c| {
                        if (ecs.transforms.get(e)) |t| {
                            switch (c.shape) {
                                .Circle => |r| rl.drawCircleV(t.position, r, if (c.mode == .Solid) .red else .blue),
                                .Rectangle => |r| rl.drawRectangleV(t.position.subtract(r), r.scale(2), if (c.mode == .Solid) .red else .blue),
                            }
                        }
                    }
                }
                rl.drawText("colliders", 0, 20, 50, .white);
            },
            3 => rl.drawText("discreet", 0, 20, 50, .white),
            else => {},
        }
        draw_ui(&eui, &ecs, renders);
        rl.endDrawing();

        renders.clean();
    }
}
