const std = @import("std");
const network = @import("network");
const packet = @import("packet.zig");

pub fn Client(comptime T: type) type {
    return struct {
        fn log_data_info(_: *Self, buff: []const u8, from: network.EndPoint) packet.PacketError!void {
            const ip = from.address.ipv4.value;
            std.log.info("received '{s}' from: {d}.{d}.{d}.{d}:{d}", .{ buff, ip[0], ip[1], ip[2], ip[3], from.port });
        }

        socket: network.Socket,
        target: ?network.EndPoint = null,
        ctx: *T,

        handle_packet_cb: *const fn (*Self, []const u8, network.EndPoint) packet.PacketError!void,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, ctx: *T) !Self {
            return .{
                .allocator = allocator,
                .socket = try network.Socket.create(.ipv4, .udp),
                .handle_packet_cb = log_data_info,
                .ctx = ctx,
            };
        }

        pub fn connect(self: *Self, addr: []const u8, port: u16, connect_data: []const u8) void {
            self.target = .{ .address = network.Address.parse(addr) catch unreachable, .port = port };
            self.send(connect_data);
        }

        fn sendto(self: *Self, target: network.EndPoint, data: []const u8) void {
            _ = self.socket.sendTo(target, data) catch std.log.err("error sending data!", .{});
        }

        /// sends to self.target
        pub fn send(self: *Self, data: []const u8) void {
            if (self.target) |target| {
                self.sendto(target, data);
            } else std.log.debug("trying to send data without a set target", .{});
        }

        pub fn set_read_timeout(self: *Self, timeout: u32) void {
            self.socket.setReadTimeout(timeout) catch unreachable;
        }

        pub fn listen(self: *Self) !void {
            const socket = self.socket;
            const BUFF_SIZE = 1024;

            var buff: [BUFF_SIZE]u8 = undefined;

            const from = try socket.receiveFrom(&buff);
            std.debug.assert(from.numberOfBytes <= BUFF_SIZE);

            try self.handle_packet_cb(self, buff[0..from.numberOfBytes], from.sender);
        }
    };
}
