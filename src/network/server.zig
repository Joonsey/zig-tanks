const std = @import("std");
const network = @import("network");

const PacketError = @import("packet.zig").PacketError;

pub fn Server(comptime T: type) type {
    return struct {
        fn log_data_info(_: *Self, buff: []const u8, from: network.EndPoint) PacketError!void {
            const ip = from.address.ipv4.value;
            std.log.info("received '{s}' from: {d}.{d}.{d}.{d}:{d}", .{ buff, ip[0], ip[1], ip[2], ip[3], from.port });
        }
        const Self = @This();

        clients: std.AutoHashMap(network.EndPoint, i64),
        socket: network.Socket,

        ctx: *T,

        handle_packet_cb: *const fn (*Self, []const u8, network.EndPoint) PacketError!void,

        allocator: std.mem.Allocator,

        pub fn init(port: u16, allocator: std.mem.Allocator, ctx: *T) !Self {
            var socket = try network.Socket.create(.ipv4, .udp);
            try socket.bind(.{ .address = .{ .ipv4 = network.Address.IPv4.any }, .port = port });

            return .{
                .socket = socket,
                .allocator = allocator,
                .clients = std.AutoHashMap(network.EndPoint, i64).init(allocator),
                .handle_packet_cb = log_data_info,
                .ctx = ctx,
            };
        }

        pub fn broadcast(self: Self, clients: []network.EndPoint, data: []const u8) void {
            for (clients) |client| self.send_to(client, data);
        }

        pub fn set_read_timeout(self: *Self, timeout: u32) void {
            self.socket.setReadTimeout(timeout) catch unreachable;
        }

        /// will propogate error from socket.receiveFrom
        /// and handle packet callback
        /// can raise error.WouldBlock if set_read_timeout is set
        /// the server will just naively add clients to the known client list if packet is successfully handled.
        ///
        /// This is because we are presuming a udp NAT punching peer to peer solution,
        /// so the presumption is that the user would have first have had to reached out to the client in the first place to even get packets routed to us.
        ///
        /// if the users wishes they can authorize within the callback and throw an error to interupt the client being added
        /// but again it's an opt-in feature as we presume authentication via the NAT
        pub fn listen(self: *Self) !void {
            const socket = self.socket;
            const BUFF_SIZE = 1024;

            var buff: [BUFF_SIZE]u8 = undefined;

            const from = try socket.receiveFrom(&buff);
            std.debug.assert(from.numberOfBytes <= BUFF_SIZE);

            try self.handle_packet_cb(self, buff[0..from.numberOfBytes], from.sender);
            try self.clients.put(from.sender, std.time.microTimestamp());
        }

        pub fn send_to(self: Self, to: network.EndPoint, data: []const u8) void {
            _ = self.socket.sendTo(to, data) catch unreachable;
        }

        pub fn deinit(self: *Self) void {
            self.socket.close();
            self.clients.clearAndFree();
        }
    };
}
