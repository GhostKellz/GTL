const std = @import("std");

pub const Transport = @import("transport.zig");
pub const Events = @import("events.zig");
pub const Auth = @import("auth.zig");
pub const Session = @import("session.zig");

pub const ConnectOpts = struct {
    endpoint: []const u8,
    token: ?[]const u8 = null,
    transport_preference: TransportType = .auto,
    timeout_ms: u32 = 5000,
};

pub const TransportType = enum {
    auto,
    stdio,
    tcp,
    websocket,
    grpc,
    sse,
    quic,
};

pub const GTLError = error{
    InvalidToken,
    ConnectionFailed,
    TransportUnavailable,
    SessionExpired,
    ProviderTimeout,
    OutOfMemory,
};

pub fn connect(allocator: std.mem.Allocator, opts: ConnectOpts) !Transport.Client {
    return Transport.Client.init(allocator, opts);
}