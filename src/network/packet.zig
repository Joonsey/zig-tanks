const std = @import("std");
const CRC32 = std.hash.Crc32;

const network = @import("network");

pub const PacketError = error{
    DeserializationError,
    AuthorizationError,
    BadInput,
    OutOfMemory,
    InvalidMagicBytes,
    InvalidChecksum,
    EndOfStream,
    NoSpaceLeft,
};

pub const PacketConfig = struct {
    T: type,
    magic_bytes: u32 = 0xDEADBEEF,
};

pub fn PacketHeader(config: PacketConfig) type {
    return packed struct {
        magic: u32,
        header_size: u16,
        payload_size: u32,
        packet_type: config.T,
        checksum: u32,

        const Self = @This();

        pub fn init(packet_type: config.T, payload_size: u32, checksum: u32) !Self {
            return .{
                .magic = config.magic_bytes,
                .header_size = @sizeOf(Self),
                .payload_size = payload_size,
                .packet_type = packet_type,
                .checksum = checksum,
            };
        }
    };
}

pub fn DefaultPacket(T: type) type {
    return Packet(.{ .T = T });
}

pub fn Packet(config: PacketConfig) type {
    const PacketHeaderType = PacketHeader(config);
    return struct {
        header: PacketHeaderType,
        payload: []const u8,

        const Self = @This();

        pub fn init(packet_type: config.T, payload: []const u8) !Self {
            const hash = CRC32.hash(payload);
            return .{
                .header = try PacketHeaderType.init(packet_type, @intCast(payload.len), hash),
                .payload = payload,
            };
        }

        /// caller is responsible for freeing after this is called
        pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            const buffer = try allocator.alloc(u8, self.header.header_size + self.header.payload_size);
            errdefer allocator.free(buffer);
            var stream = std.io.fixedBufferStream(buffer);

            const writer = stream.writer();

            try writer.writeStructEndian(self.header, .little);
            try writer.writeAll(self.payload);
            return stream.getWritten();
        }

        /// caller is responsible for freeing after this is called
        pub fn deserialize(data: []const u8, allocator: std.mem.Allocator) !Self {
            var stream = std.io.fixedBufferStream(data);
            const reader = stream.reader();

            const header = try reader.readStructEndian(PacketHeaderType, .little);
            if (header.magic != config.magic_bytes) return error.InvalidMagicBytes;

            const payload = try allocator.alloc(u8, header.payload_size);
            errdefer allocator.free(payload);
            try reader.readNoEof(payload);

            if (header.checksum != CRC32.hash(payload)) return error.InvalidChecksum;

            return .{
                .header = header,
                .payload = payload,
            };
        }

        pub fn free(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.payload);
        }
    };
}

/// returned slice's lifetime will be as long as buffer argument
pub fn serialize_payload(buffer: []u8, payload: anytype) ![]u8 {
    @memset(buffer, 0);
    var stream = std.io.fixedBufferStream(buffer);

    const T = @TypeOf(payload);
    const info = @typeInfo(T);
    const writer = stream.writer();
    switch (info) {
        .@"struct" => try writer.writeStructEndian(payload, .little),
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice) {
                for (payload) |payload_struct| try writer.writeStructEndian(payload_struct, .little);
            } else {
                return error.InvalidType;
            }
        },
        else => return error.InvalidType,
    }

    return stream.getWritten();
}

pub fn deserialize_payload(payload: []const u8, comptime T: type) !T {
    var stream = std.io.fixedBufferStream(payload);

    return try stream.reader().readStructEndian(T, .little);
}
