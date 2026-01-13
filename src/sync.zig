const std = @import("std");
const rl = @import("raylib");
const ECS = @import("entity.zig").ECS;
const _entity = @import("entity.zig");
const Entity = _entity.Entity;
const Transform = _entity.Transform;
const Event = _entity.Event;

const network = @import("network");
const Client = @import("network/client.zig").Client;
const _packet = @import("network/packet.zig");
const PacketError = _packet.PacketError;

const consts = @import("consts.zig");
const shared = @import("network/shared.zig");

const TurretSystem = @import("turret.zig").TurretSystem;

pub const GameClientContext = struct {
    num_players: usize = 0,
    update_count: u32 = 0,

    syncs: [consts.MAX_PLAYERS]shared.Sync = undefined,

    lock: std.Thread.RwLock = .{},

    allocator: std.mem.Allocator,
};

pub const GameClient = Client(GameClientContext);

fn handle_packet(self: *GameClient, data: []const u8, sender: network.EndPoint) PacketError!void {
    const ctx = self.ctx;
    const packet: shared.Packet = try .deserialize(data, ctx.allocator);
    defer packet.free(ctx.allocator);
    _ = sender;

    switch (packet.header.packet_type) {
        .ACK => {},
        .SYNC => {
            const size = @sizeOf(shared.Sync);
            const count: usize = packet.payload.len / size;
            ctx.num_players = count;

            ctx.lock.lockShared();
            for (0..count) |i| ctx.syncs[i] = try _packet.deserialize_payload(packet.payload[i * size .. size * (1 + i)], shared.Sync);
            ctx.lock.unlockShared();
        },
        .FIRE => {
            std.log.debug("GOT FIRE", .{});
        },
    }
}

pub const SyncSystem = struct {
    client: GameClient,
    ctx: *GameClientContext,

    player_map: std.AutoHashMapUnmanaged(consts.NetworkId, Entity),

    client_thread: std.Thread = undefined,
    should_stop: bool = false,
    is_running: bool = false,

    player_network_id: consts.NetworkId = 0,

    turrets: *TurretSystem,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, turrets: *TurretSystem) Self {
        const ctx = allocator.create(GameClientContext) catch unreachable;
        ctx.* = .{ .allocator = allocator };
        var client = GameClient.init(allocator, ctx) catch unreachable;
        client.handle_packet_cb = handle_packet;

        return .{
            .client = client,
            .ctx = ctx,
            .player_map = .{},
            .turrets = turrets,
        };
    }

    pub fn on_event(ctx: *anyopaque, event: Event, ecs: *ECS) void {
        _ = ecs;
        const self: *Self = @ptrCast(@alignCast(ctx));
        switch (event) {
            .Fire => |f| {
                if (self.player_map.get(self.player_network_id)) |e| if (e == f.owner) return;
                self.send(.FIRE, shared.Fire{ .owner = f.owner });
            },
            else => {},
        }
    }

    pub fn update(ctx: *anyopaque, ecs: *ECS) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const syncs = self.ctx.syncs[0..self.ctx.num_players];
        for (syncs) |sync| {
            if (sync.id == 0) continue;
            if (sync.id == self.player_network_id) continue;

            if (self.player_map.get(sync.id)) |e| {
                if (ecs.transforms.get(e)) |t| t.* = sync.update.transform;
                if (ecs.ssprite.get(e)) |s| s.* = sync.update.sprite;
                if (ecs.rigidbody.get(e)) |s| s.* = sync.update.rigidbody;

                const turret_id = self.turrets.map.get(e) orelse e;
                if (ecs.transforms.get(turret_id)) |t| t.* = sync.update.turret_transform;
                if (ecs.ssprite.get(turret_id)) |s| s.* = sync.update.turret_sprite;
            } else {
                const e = ecs.create();
                _ = ecs.transforms.add(e, sync.update.transform);
                _ = ecs.ssprite.add(e, sync.update.sprite);
                _ = ecs.collider.add(e, .{ .mode = .Solid, .shape = .{ .Rectangle = .init(4, 4) } });
                _ = ecs.rigidbody.add(e, sync.update.rigidbody);
                self.player_map.put(self.ctx.allocator, sync.id, e) catch unreachable;

                self.turrets.create(ecs, e);
            }
        }

        self.send_player_update(0, ecs);
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        allocator.destroy(self.ctx);
    }

    fn listen(self: *Self) void {
        while (!self.should_stop) {
            self.ctx.update_count += 1;
            self.client.listen() catch |err| switch (err) {
                error.WouldBlock => continue,
                else => {
                    std.log.err("client.listen failed with error {}", .{err});
                    self.should_stop = true;
                },
            };
        }

        self.is_running = false;
    }

    pub fn connect(self: *Self, hostname: []const u8, port: u16, player_id: consts.NetworkId) void {
        var buf: [1024]u8 = undefined;
        const ack = shared.Ack{ .id = player_id };

        self.player_network_id = player_id;

        const packet = shared.Packet.init(.ACK, _packet.serialize_payload(&buf, ack) catch unreachable) catch unreachable;
        const data = packet.serialize(self.ctx.allocator) catch unreachable;
        defer self.ctx.allocator.free(data);
        self.client.connect(hostname, port, data);
    }

    pub fn disconnect(self: *Self) void {
        if (!self.is_running) return;
        self.should_stop = true;
        std.log.debug("disconnecting from server...", .{});

        self.client_thread.join();
        std.log.debug("disconnected", .{});

        self.player_map.clearAndFree(self.ctx.allocator);
    }

    pub fn send_player_update(self: *Self, entity: Entity, ecs: *ECS) void {
        const turret_id = self.turrets.map.get(entity) orelse entity;

        const upd = shared.Update{
            .sprite = ecs.ssprite.get(entity).?.*,
            .transform = ecs.transforms.get(entity).?.*,
            .rigidbody = ecs.rigidbody.get(entity).?.*,

            .turret_sprite = ecs.ssprite.get(turret_id).?.*,
            .turret_transform = ecs.transforms.get(turret_id).?.*,
        };

        self.send(.SYNC, upd);
    }

    pub fn send(self: *Self, t: shared.PacketType, content: anytype) void {
        var buf: [1024]u8 = undefined;

        const packet = shared.Packet.init(t, _packet.serialize_payload(&buf, content) catch unreachable) catch unreachable;
        const data = packet.serialize(self.ctx.allocator) catch unreachable;
        defer self.ctx.allocator.free(data);

        self.client.send(data);
    }

    pub fn start(self: *Self) void {
        if (self.is_running) return;
        self.is_running = true;
        self.client.set_read_timeout(1000);
        self.client_thread = std.Thread.spawn(.{}, Self.listen, .{self}) catch unreachable;
    }
};
