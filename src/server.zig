const std = @import("std");
const rl = @import("raylib");
const ECS = @import("entity.zig").ECS;
const _entity = @import("entity.zig");
const Entity = _entity.Entity;
const Transform = _entity.Transform;
const Event = _entity.Event;

const network = @import("network");
const NetworkServer = @import("network/server.zig").Server;
const PacketError = @import("network/packet.zig").PacketError;
const _packet = @import("network/packet.zig");

const consts = @import("consts.zig");
const shared = @import("network/shared.zig");

const Player = struct {
    id: consts.NetworkId,
    index: usize,
};

pub const GameServerContext = struct {
    num_players: usize = 0,
    update_count: u32 = 0,

    syncs: [consts.MAX_PLAYERS]shared.Sync = undefined,
    players: std.AutoHashMapUnmanaged(network.EndPoint, Player),
};
pub const GameServer = NetworkServer(GameServerContext);

fn handle_packet(self: *GameServer, data: []const u8, sender: network.EndPoint) PacketError!void {
    const ctx = self.ctx;
    const packet: shared.Packet = try .deserialize(data, self.allocator);
    defer packet.free(self.allocator);

    switch (packet.header.packet_type) {
        .ACK => {
            const payload = try _packet.deserialize_payload(packet.payload, shared.Ack);
            std.log.debug("{d} has asked to connect", .{payload.id});
            if (ctx.players.size >= consts.MAX_PLAYERS) {
                std.log.warn("{d} got rejected, because server is full", .{payload.id});
            } else {
                var iter = ctx.players.iterator();
                var exists = false;
                while (iter.next()) |player| {
                    if (player.value_ptr.id == payload.id) {
                        std.log.warn("{d} got rejected, because duplicate id", .{payload.id});
                        exists = true;
                    }
                }
                if (!exists) {
                    ctx.players.put(self.allocator, sender, .{ .id = payload.id, .index = ctx.num_players }) catch unreachable;
                    ctx.num_players += 1;
                }
            }
        },
        .SYNC => {
            if (ctx.players.get(sender)) |player| {
                const payload = try _packet.deserialize_payload(packet.payload, shared.Update);
                ctx.syncs[player.index] = .{ .id = player.id, .update = payload };
            }
        },
        .FIRE => {
            var iter = ctx.players.keyIterator();
            var players: [consts.MAX_PLAYERS]network.EndPoint = undefined;

            var i: usize = 0;
            while (iter.next()) |p| {
                players[i] = p.*;
                i += 1;
            }

            self.broadcast(players[0..i], data);
        },
    }
}

pub const Server = struct {
    server: GameServer,
    ctx: *GameServerContext,

    server_thread: std.Thread = undefined,
    should_stop: bool = false,
    is_running: bool = false,

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
    ) Self {
        const ctx = allocator.create(GameServerContext) catch unreachable;
        ctx.* = .{ .players = .{}, .syncs = std.mem.zeroes([consts.MAX_PLAYERS]shared.Sync) };
        var server = GameServer.init(consts.GAME_PORT, allocator, ctx) catch unreachable;
        server.handle_packet_cb = handle_packet;

        return .{ .server = server, .ctx = ctx, .allocator = allocator };
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator) void {
        if (!self.should_stop) self.stop();
        self.server.deinit();

        self.ctx.players.deinit(self.allocator);
        allocator.destroy(self.ctx);
    }

    pub fn start(self: *Self) void {
        if (self.is_running) return;
        self.is_running = true;
        self.server.set_read_timeout(1000);
        self.server_thread = std.Thread.spawn(.{}, Self.listen, .{self}) catch unreachable;
    }

    fn broadcast(self: *Self, data: []const u8) void {
        var iter = self.ctx.players.iterator();
        while (iter.next()) |player| {
            self.server.send_to(player.key_ptr.*, data);
        }
    }

    fn sync_players(self: *Self) void {
        // first sync packets may be - out of sync, as they havent been 'updated' yet.
        // although I don't really think this is an issue?
        //
        // sync players may want to send time-sensetive information at times where we are prone for disconnect
        // only sharing update Sync packets during game, at which point new .ack packets are dissallowed, maybe?
        var buffer: [1024]u8 = undefined;
        const packet = shared.Packet.init(.SYNC, _packet.serialize_payload(&buffer, self.ctx.syncs[0..self.ctx.num_players]) catch unreachable) catch unreachable;

        const data = packet.serialize(self.allocator) catch unreachable;
        self.broadcast(data);
        defer self.allocator.free(data);
    }

    fn listen(self: *Self) void {
        while (!self.should_stop) {
            self.ctx.update_count += 1;
            //switch (self.ctx.state.state) {
            //    .Lobby, .Starting => {
            //        if (self.ctx.update_count % 500 == 0) {
            //            self.matchmaking_keepalive();
            //            self.sync_lobby();
            //        }
            //        cleanup_dead_clients(self);
            //    },
            //    .Playing, .Finishing => if (self.ctx.num_players > 0) {
            //        self.sync_players();
            //    },
            //}
            // self.update_state();sync
            self.sync_players();
            self.server.listen() catch |err| switch (err) {
                error.WouldBlock => continue,
                else => {
                    std.log.err("server.listen failed with error {}", .{err});
                    self.should_stop = true;
                },
            };
        }

        self.is_running = false;
    }

    pub fn stop(self: *Self) void {
        if (!self.is_running) return;
        self.should_stop = true;
        std.log.debug("closing server ...", .{});

        self.server_thread.join();
        std.log.debug("server closed", .{});
    }
};
