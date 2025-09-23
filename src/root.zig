//! Ghost Transport Layer (GTL) - ENHANCED multiprotocol transport for Ghost ecosystem
const std = @import("std");

// Re-export ENHANCED GTL modules
pub const gtl = @import("gtl.zig");
pub const Transport = @import("transport.zig");
pub const Events = @import("events.zig");
pub const Auth = @import("auth.zig");
pub const Session = @import("session.zig");
pub const Enhanced = @import("enhanced_transports.zig");
pub const providers = @import("providers.zig");
pub const failover = @import("failover.zig");
pub const metrics = @import("metrics.zig");

// ENHANCED Main API
pub const connect = gtl.connect;
pub const ConnectOpts = gtl.ConnectOpts;
pub const TransportType = gtl.TransportType;
pub const GTLError = gtl.GTLError;

// ENHANCED Event types
pub const GTLEvent = Events.GTLEvent;
pub const GTLFrame = Events.GTLFrame;
pub const EventHandler = Events.EventHandler;

// ENHANCED Auth types
pub const GhostToken = Auth.GhostToken;
pub const TokenScope = Auth.TokenScope;

// ENHANCED Transport types
pub const TcpTransport = Enhanced.TcpTransport;
pub const WebSocketTransport = Enhanced.WebSocketTransport;
pub const GrpcTransport = Enhanced.GrpcTransport;
pub const SseTransport = Enhanced.SseTransport;
pub const QuicTransport = Enhanced.QuicTransport;

// Legacy function for compatibility
pub fn bufferedPrint() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("GTL (Ghost Transport Layer) v0.1 - Ready for AI communication!\n", .{});
    try stdout.flush();
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

test "enhanced GTL transports" {
    const allocator = std.testing.allocator;

    // Test enhanced session
    var session = try Session.Session.init(allocator, "gpt-4");
    defer session.deinit();
    try std.testing.expect(std.mem.eql(u8, session.model, "gpt-4"));

    // Test enhanced transport initialization
    var tcp_transport = TcpTransport.init(allocator);
    defer tcp_transport.deinit();

    var ws_transport = WebSocketTransport.init(allocator);
    defer ws_transport.deinit();

    var grpc_transport = GrpcTransport.init(allocator);
    defer grpc_transport.deinit();

    try std.testing.expect(true); // All transports initialized successfully
}
