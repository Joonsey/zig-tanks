const std = @import("std");

pub fn BitFlag(comptime E: type) type {
    comptime if (@typeInfo(E) != .@"enum") @compileError("");
    const enum_info = @typeInfo(E).@"enum";
    const Int = enum_info.tag_type;

    return struct {
        bits: Int = 0,

        const Self = @This();

        pub fn empty() Self {
            return .{};
        }

        pub fn from_int(int: Int) Self {
            return .{ .bits = int };
        }
        pub fn set(self: *Self, flag: E) void {
            self.bits |= @intFromEnum(flag);
        }

        pub fn clear(self: *Self, flag: E) void {
            self.bits &= ~@intFromEnum(flag);
        }

        pub fn toggle(self: *Self, flag: E) void {
            self.bits ^= @intFromEnum(flag);
        }

        pub fn has(self: *Self, flag: E) bool {
            return (self.bits & @intFromEnum(flag)) != 0;
        }
    };
}
