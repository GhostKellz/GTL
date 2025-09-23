const std = @import("std");
const Events = @import("events.zig");
const Auth = @import("auth.zig");
const Session = @import("session.zig");
const gtl = @import("gtl.zig");
const enhanced = @import("enhanced_transports.zig");

// Import enhanced transport types
pub const TcpTransport = enhanced.TcpTransport;
pub const WebSocketTransport = enhanced.WebSocketTransport;
pub const GrpcTransport = enhanced.GrpcTransport;
pub const SseTransport = enhanced.SseTransport;
pub const QuicTransport = enhanced.QuicTransport;

pub const TransportError = error{
    ConnectionFailed,
    SendFailed,
    ReceiveFailed,
    UnsupportedTransport,
    Timeout,
};

pub const Client = struct {
    transport: Transport,
    allocator: std.mem.Allocator,
    session_manager: Session.SessionManager,
    auth_validator: Auth.AuthValidator,

    pub fn init(allocator: std.mem.Allocator, opts: gtl.ConnectOpts) !Client {
        const transport = try selectTransport(allocator, opts);

        return Client{
            .transport = transport,
            .allocator = allocator,
            .session_manager = Session.SessionManager.init(allocator),
            .auth_validator = Auth.AuthValidator.init(allocator),
        };
    }

    pub fn deinit(self: *Client) void {
        self.transport.deinit();
        self.session_manager.deinit();
    }

    pub fn unary(self: *Client, route: []const u8, req: []const u8) ![]u8 {
        return self.transport.unary(route, req);
    }

    pub fn serverStream(self: *Client, route: []const u8, req: []const u8, handler: Events.EventHandler) !void {
        return self.transport.serverStream(route, req, handler);
    }

    pub fn createSession(self: *Client, model: []const u8) !*Session.Session {
        return self.session_manager.createSession(model);
    }

    pub fn validateAuth(self: *Client, token: []const u8) !Auth.GhostToken {
        return self.auth_validator.validateToken(token);
    }
};

pub const Transport = union(gtl.TransportType) {
    auto: void,
    stdio: StdioTransport,
    tcp: TcpTransport,
    websocket: WebSocketTransport,
    grpc: GrpcTransport,
    sse: SseTransport,
    quic: QuicTransport,

    pub fn deinit(self: *Transport) void {
        switch (self.*) {
            .stdio => |*t| t.deinit(),
            .tcp => |*t| t.deinit(),
            .websocket => |*t| t.deinit(),
            .grpc => |*t| t.deinit(),
            .sse => |*t| t.deinit(),
            .quic => |*t| t.deinit(),
            else => {},
        }
    }

    pub fn unary(self: *Transport, route: []const u8, req: []const u8) ![]u8 {
        switch (self.*) {
            .stdio => |*t| return t.unary(route, req),
            .tcp => |*t| return t.unary(route, req),
            .websocket => |*t| return t.unary(route, req),
            .grpc => |*t| return t.unary(route, req),
            .sse => |*t| return t.unary(route, req),
            .quic => |*t| return t.unary(route, req),
            else => return TransportError.UnsupportedTransport,
        }
    }

    pub fn serverStream(self: *Transport, route: []const u8, req: []const u8, handler: Events.EventHandler) !void {
        switch (self.*) {
            .stdio => |*t| return t.serverStream(route, req, handler),
            .tcp => |*t| return t.serverStream(route, req, handler),
            .websocket => |*t| return t.serverStream(route, req, handler),
            .grpc => |*t| return t.serverStream(route, req, handler),
            .sse => |*t| return t.serverStream(route, req, handler),
            .quic => |*t| return t.serverStream(route, req, handler),
            else => return TransportError.UnsupportedTransport,
        }
    }

    pub fn connect(self: *Transport, endpoint: []const u8) !void {
        switch (self.*) {
            .tcp => |*t| try t.connect(endpoint),
            .websocket => |*t| try t.connect(endpoint),
            .grpc => |*t| try t.connect(endpoint),
            .sse => |*t| try t.connect(endpoint),
            .quic => |*t| try t.connect(endpoint),
            else => {}, // stdio doesn't need connection
        }
    }
};

pub const StdioTransport = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StdioTransport {
        return StdioTransport{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StdioTransport) void {
        _ = self;
    }

    pub fn unary(self: *StdioTransport, route: []const u8, req: []const u8) ![]u8 {
        // Mock response for MVP
        return std.fmt.allocPrint(self.allocator, "RESPONSE to {s}: {s}", .{ route, req });
    }

    pub fn serverStream(self: *StdioTransport, route: []const u8, req: []const u8, handler: Events.EventHandler) !void {
        _ = self;
        _ = route;
        _ = req;

        // Simulate streaming events for MVP
        handler(Events.GTLEvent{ .status = .{ .state = .streaming } });
        handler(Events.GTLEvent{ .token = .{ .text = "Hello" } });
        handler(Events.GTLEvent{ .token = .{ .text = " from" } });
        handler(Events.GTLEvent{ .token = .{ .text = " GTL!" } });
        handler(Events.GTLEvent.done);
    }
};

fn selectTransport(allocator: std.mem.Allocator, opts: gtl.ConnectOpts) !Transport {
    switch (opts.transport_preference) {
        .auto => {
            // Smart transport selection based on endpoint
            if (std.mem.startsWith(u8, opts.endpoint, "stdio://")) {
                return Transport{ .stdio = StdioTransport.init(allocator) };
            } else if (std.mem.startsWith(u8, opts.endpoint, "tcp://")) {
                var transport = Transport{ .tcp = TcpTransport.init(allocator) };
                try transport.connect(opts.endpoint);
                return transport;
            } else if (std.mem.startsWith(u8, opts.endpoint, "ws://") or std.mem.startsWith(u8, opts.endpoint, "wss://")) {
                var transport = Transport{ .websocket = WebSocketTransport.init(allocator) };
                try transport.connect(opts.endpoint);
                return transport;
            } else if (std.mem.startsWith(u8, opts.endpoint, "grpc://") or std.mem.startsWith(u8, opts.endpoint, "grpcs://")) {
                var transport = Transport{ .grpc = GrpcTransport.init(allocator) };
                try transport.connect(opts.endpoint);
                return transport;
            } else if (std.mem.startsWith(u8, opts.endpoint, "sse://")) {
                var transport = Transport{ .sse = SseTransport.init(allocator) };
                try transport.connect(opts.endpoint);
                return transport;
            } else if (std.mem.startsWith(u8, opts.endpoint, "quic://")) {
                var transport = Transport{ .quic = QuicTransport.init(allocator) };
                try transport.connect(opts.endpoint);
                return transport;
            } else {
                // Default to stdio for local development
                return Transport{ .stdio = StdioTransport.init(allocator) };
            }
        },
        .stdio => {
            return Transport{ .stdio = StdioTransport.init(allocator) };
        },
        .tcp => {
            var transport = Transport{ .tcp = TcpTransport.init(allocator) };
            try transport.connect(opts.endpoint);
            return transport;
        },
        .websocket => {
            var transport = Transport{ .websocket = WebSocketTransport.init(allocator) };
            try transport.connect(opts.endpoint);
            return transport;
        },
        .grpc => {
            var transport = Transport{ .grpc = GrpcTransport.init(allocator) };
            try transport.connect(opts.endpoint);
            return transport;
        },
        .sse => {
            var transport = Transport{ .sse = SseTransport.init(allocator) };
            try transport.connect(opts.endpoint);
            return transport;
        },
        .quic => {
            var transport = Transport{ .quic = QuicTransport.init(allocator) };
            try transport.connect(opts.endpoint);
            return transport;
        },
    }
}