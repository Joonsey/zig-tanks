const consts = @import("../consts.zig");
const P = @import("packet.zig").Packet;

const _entity = @import("../entity.zig");
const assets = @import("../assets.zig");

pub const PacketType = enum(u16) {
    ACK,
    SYNC,
    FIRE,
};

pub const Packet = P(.{ .T = PacketType, .magic_bytes = 0x4C564C88 });

pub const Update = extern struct {
    transform: _entity.Transform,
    rigidbody: _entity.RigidBody,
    sprite: assets.Assets,

    turret_transform: _entity.Transform,
    turret_sprite: assets.Assets,
};

pub const Sync = extern struct {
    id: consts.NetworkId,
    update: Update,
};

pub const Ack = extern struct {
    id: consts.NetworkId,
};

pub const Fire = extern struct {
    owner: consts.NetworkId,
};
