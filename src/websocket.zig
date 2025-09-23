const std = @import("std");
const tcp = @import("tcp.zig");
const Events = @import("events.zig");

pub const WebSocketError = error{
    HandshakeFailed,
    InvalidFrame,
    ConnectionClosed,
    InvalidOpcode,
};

pub const WebSocketOpcode = enum(u8) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xa,
};

pub const WebSocketFrame = struct {
    fin: bool,
    opcode: WebSocketOpcode,
    masked: bool,
    payload: []const u8,

    pub fn parse(data: []const u8) !WebSocketFrame {
        if (data.len < 2) return WebSocketError.InvalidFrame;

        const byte1 = data[0];
        const byte2 = data[1];

        const fin = (byte1 & 0x80) != 0;
        const opcode = @as(WebSocketOpcode, @enumFromInt(byte1 & 0x0F));
        const masked = (byte2 & 0x80) != 0;
        var payload_len = @as(usize, byte2 & 0x7F);

        var offset: usize = 2;

        // Extended payload length
        if (payload_len == 126) {
            if (data.len < offset + 2) return WebSocketError.InvalidFrame;
            payload_len = std.mem.readInt(u16, data[offset..offset+2], .big);
            offset += 2;
        } else if (payload_len == 127) {
            if (data.len < offset + 8) return WebSocketError.InvalidFrame;
            payload_len = std.mem.readInt(u64, data[offset..offset+8], .big);
            offset += 8;
        }

        // Masking key (if present)
        if (masked) {
            if (data.len < offset + 4) return WebSocketError.InvalidFrame;
            offset += 4; // Skip mask for now
        }

        if (data.len < offset + payload_len) return WebSocketError.InvalidFrame;

        return WebSocketFrame{
            .fin = fin,
            .opcode = opcode,
            .masked = masked,
            .payload = data[offset..offset + payload_len],
        };
    }

    pub fn encode(self: WebSocketFrame, allocator: std.mem.Allocator) ![]u8 {
        var frame = std.ArrayList(u8).init(allocator);
        defer frame.deinit();

        // First byte: FIN + opcode
        var byte1: u8 = @intFromEnum(self.opcode);
        if (self.fin) byte1 |= 0x80;
        try frame.append(byte1);

        // Second byte: MASK + payload length
        const payload_len = self.payload.len;
        var byte2: u8 = 0;
        if (self.masked) byte2 |= 0x80;

        if (payload_len < 126) {
            byte2 |= @as(u8, @intCast(payload_len));
            try frame.append(byte2);
        } else if (payload_len < 65536) {
            byte2 |= 126;
            try frame.append(byte2);
            try frame.appendSlice(std.mem.asBytes(&std.mem.nativeToBig(u16, @as(u16, @intCast(payload_len)))));
        } else {
            byte2 |= 127;
            try frame.append(byte2);
            try frame.appendSlice(std.mem.asBytes(&std.mem.nativeToBig(u64, @as(u64, @intCast(payload_len)))));
        }

        // Payload
        try frame.appendSlice(self.payload);

        return try frame.toOwnedSlice();
    }
};

pub const WebSocketTransport = struct {
    tcp_client: tcp.TcpClient,
    allocator: std.mem.Allocator,
    connected: bool,

    pub fn init(allocator: std.mem.Allocator) WebSocketTransport {
        return WebSocketTransport{
            .tcp_client = tcp.TcpClient.init(allocator),
            .allocator = allocator,
            .connected = false,
        };
    }

    pub fn connect(self: *WebSocketTransport, url: []const u8) !void {
        // Parse WebSocket URL: ws://host:port/path
        var url_parts = std.mem.splitSequence(u8, url, "://");
        const scheme = url_parts.next() orelse return WebSocketError.HandshakeFailed;
        const rest = url_parts.next() orelse return WebSocketError.HandshakeFailed;

        if (!std.mem.eql(u8, scheme, "ws")) {
            return WebSocketError.HandshakeFailed;
        }

        var host_port_path = std.mem.splitSequence(u8, rest, "/");
        const host_port = host_port_path.next() orelse return WebSocketError.HandshakeFailed;
        const path = host_port_path.next() orelse "";

        var host_port_split = std.mem.splitSequence(u8, host_port, ":");
        const host = host_port_split.next() orelse return WebSocketError.HandshakeFailed;
        const port_str = host_port_split.next() orelse "80";
        const port = std.fmt.parseInt(u16, port_str, 10) catch 80;

        // Connect TCP
        try self.tcp_client.connect(host, port);

        // WebSocket handshake
        try self.performHandshake(host, path);
        self.connected = true;
    }

    pub fn disconnect(self: *WebSocketTransport) void {
        if (self.connected) {
            // Send close frame
            const close_frame = WebSocketFrame{
                .fin = true,
                .opcode = .close,
                .masked = false,
                .payload = "",
            };

            if (close_frame.encode(self.allocator)) |frame_data| {
                defer self.allocator.free(frame_data);
                self.tcp_client.send(frame_data) catch {};
            } else |_| {}

            self.tcp_client.disconnect();
            self.connected = false;
        }
    }

    pub fn sendText(self: *WebSocketTransport, text: []const u8) !void {
        if (!self.connected) return WebSocketError.ConnectionClosed;

        const frame = WebSocketFrame{
            .fin = true,
            .opcode = .text,
            .masked = false,
            .payload = text,
        };

        const frame_data = try frame.encode(self.allocator);
        defer self.allocator.free(frame_data);

        try self.tcp_client.send(frame_data);
    }

    pub fn sendGTLEvent(self: *WebSocketTransport, event: Events.GTLFrame) !void {
        const json = try event.toJson(self.allocator);
        defer self.allocator.free(json);

        try self.sendText(json);
    }

    pub fn recvFrame(self: *WebSocketTransport) !WebSocketFrame {
        if (!self.connected) return WebSocketError.ConnectionClosed;

        // Read frame header (minimum 2 bytes)
        var header: [14]u8 = undefined; // Max header size
        _ = try self.tcp_client.recv(header[0..2]);

        var header_len: usize = 2;
        const payload_len_field = header[1] & 0x7F;

        if (payload_len_field == 126) {
            _ = try self.tcp_client.recv(header[2..4]);
            header_len = 4;
        } else if (payload_len_field == 127) {
            _ = try self.tcp_client.recv(header[2..10]);
            header_len = 10;
        }

        if ((header[1] & 0x80) != 0) { // Masked
            _ = try self.tcp_client.recv(header[header_len..header_len+4]);
            header_len += 4;
        }

        // Parse frame to get payload length
        const frame_header = try WebSocketFrame.parse(header[0..header_len]);

        // Read payload
        const payload = try self.allocator.alloc(u8, frame_header.payload.len);
        _ = try self.tcp_client.recv(payload);

        // Create complete frame data
        var complete_frame = try self.allocator.alloc(u8, header_len + payload.len);
        defer self.allocator.free(complete_frame);

        std.mem.copyForwards(u8, complete_frame[0..header_len], header[0..header_len]);
        std.mem.copyForwards(u8, complete_frame[header_len..], payload);

        return WebSocketFrame.parse(complete_frame);
    }

    pub fn serverStream(self: *WebSocketTransport, route: []const u8, req: []const u8, handler: Events.EventHandler) !void {
        // Send request as GTL frame
        const request_frame = Events.GTLFrame{
            .sid = "ws-stream",
            .event = Events.GTLEvent{ .token = .{ .text = req } },
        };

        try self.sendGTLEvent(request_frame);

        // Listen for response frames
        while (self.connected) {
            const frame = self.recvFrame() catch break;

            switch (frame.opcode) {
                .text => {
                    // Parse as GTL event
                    if (Events.GTLFrame.fromJson(self.allocator, frame.payload)) |gtl_frame| {
                        handler(gtl_frame.event);

                        // Check for done event
                        switch (gtl_frame.event) {
                            .done => break,
                            .@"error" => break,
                            else => {},
                        }
                    } else |_| {}
                },
                .close => break,
                else => {},
            }
        }

        _ = route; // Unused for now
    }

    fn performHandshake(self: *WebSocketTransport, host: []const u8, path: []const u8) !void {
        // Generate WebSocket key
        var key_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);

        var key_b64: [24]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&key_b64, &key_bytes);

        // Build handshake request
        const path_with_slash = if (path.len == 0) "/" else path;

        const request = try std.fmt.allocPrint(self.allocator,
            \\GET /{s} HTTP/1.1
            \\Host: {s}
            \\Upgrade: websocket
            \\Connection: Upgrade
            \\Sec-WebSocket-Key: {s}
            \\Sec-WebSocket-Version: 13
            \\
            \\
        , .{ path_with_slash, host, key_b64 });
        defer self.allocator.free(request);

        try self.tcp_client.send(request);

        // Read handshake response
        var response = try self.tcp_client.recvHttpResponse(self.allocator);
        defer response.deinit();

        if (response.status_code != 101) {
            return WebSocketError.HandshakeFailed;
        }
    }
};