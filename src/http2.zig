const std = @import("std");
const tcp = @import("tcp.zig");
const Events = @import("events.zig");

pub const Http2Error = error{
    ConnectionFailed,
    InvalidFrame,
    ProtocolError,
    StreamClosed,
};

pub const Http2FrameType = enum(u8) {
    data = 0x0,
    headers = 0x1,
    priority = 0x2,
    rst_stream = 0x3,
    settings = 0x4,
    push_promise = 0x5,
    ping = 0x6,
    goaway = 0x7,
    window_update = 0x8,
    continuation = 0x9,
};

pub const Http2Frame = struct {
    length: u24,
    frame_type: Http2FrameType,
    flags: u8,
    stream_id: u31,
    payload: []const u8,

    pub fn parse(data: []const u8) !Http2Frame {
        if (data.len < 9) return Http2Error.InvalidFrame;

        const length = std.mem.readInt(u24, data[0..3], .big);
        const frame_type = @as(Http2FrameType, @enumFromInt(data[3]));
        const flags = data[4];
        const stream_id = std.mem.readInt(u32, data[5..9], .big) & 0x7FFFFFFF;

        if (data.len < 9 + length) return Http2Error.InvalidFrame;

        return Http2Frame{
            .length = length,
            .frame_type = frame_type,
            .flags = flags,
            .stream_id = @intCast(stream_id),
            .payload = data[9..9 + length],
        };
    }

    pub fn encode(self: Http2Frame, allocator: std.mem.Allocator) ![]u8 {
        var frame = try allocator.alloc(u8, 9 + self.payload.len);

        // Length (24 bits)
        std.mem.writeInt(u24, frame[0..3], self.length, .big);

        // Type (8 bits)
        frame[3] = @intFromEnum(self.frame_type);

        // Flags (8 bits)
        frame[4] = self.flags;

        // Stream ID (31 bits, R bit = 0)
        std.mem.writeInt(u32, frame[5..9], @as(u32, self.stream_id), .big);

        // Payload
        std.mem.copyForwards(u8, frame[9..], self.payload);

        return frame;
    }
};

pub const Http2Transport = struct {
    tcp_client: tcp.TcpClient,
    allocator: std.mem.Allocator,
    connected: bool,
    next_stream_id: u31,
    settings_sent: bool,

    pub fn init(allocator: std.mem.Allocator) Http2Transport {
        return Http2Transport{
            .tcp_client = tcp.TcpClient.init(allocator),
            .allocator = allocator,
            .connected = false,
            .next_stream_id = 1, // Client streams are odd
            .settings_sent = false,
        };
    }

    pub fn connect(self: *Http2Transport, host: []const u8, port: u16) !void {
        try self.tcp_client.connect(host, port);

        // Send HTTP/2 connection preface
        const preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
        try self.tcp_client.send(preface);

        // Send initial SETTINGS frame
        try self.sendSettings();

        self.connected = true;
    }

    pub fn disconnect(self: *Http2Transport) void {
        if (self.connected) {
            // Send GOAWAY frame
            self.sendGoaway() catch {};
            self.tcp_client.disconnect();
            self.connected = false;
        }
    }

    pub fn unary(self: *Http2Transport, route: []const u8, req: []const u8) ![]u8 {
        if (!self.connected) return Http2Error.ConnectionFailed;

        const stream_id = self.getNextStreamId();

        // Send HEADERS frame with gRPC request
        try self.sendGrpcHeaders(stream_id, route, req.len);

        // Send DATA frame with request body
        try self.sendData(stream_id, req, true); // End stream

        // Read response
        return self.readGrpcResponse(stream_id);
    }

    pub fn serverStream(self: *Http2Transport, route: []const u8, req: []const u8, handler: Events.EventHandler) !void {
        if (!self.connected) return Http2Error.ConnectionFailed;

        const stream_id = self.getNextStreamId();

        // Send gRPC request
        try self.sendGrpcHeaders(stream_id, route, req.len);
        try self.sendData(stream_id, req, true);

        // Read streaming response
        while (self.connected) {
            const frame = self.recvFrame() catch break;

            if (frame.stream_id != stream_id) continue;

            switch (frame.frame_type) {
                .data => {
                    // Parse gRPC message
                    if (self.parseGrpcMessage(frame.payload)) |message| {
                        // Convert to GTL event
                        const event = Events.GTLEvent{ .token = .{ .text = message } };
                        handler(event);
                    } else |_| {}

                    // Check for end of stream
                    if ((frame.flags & 0x1) != 0) { // END_STREAM
                        handler(Events.GTLEvent.done);
                        break;
                    }
                },
                .headers => {
                    // Handle response headers/trailers
                    if ((frame.flags & 0x1) != 0) { // END_STREAM
                        handler(Events.GTLEvent.done);
                        break;
                    }
                },
                .rst_stream => {
                    handler(Events.GTLEvent{ .@"error" = .{ .code = "STREAM_RESET", .message = "Stream was reset" } });
                    break;
                },
                else => {},
            }
        }
    }

    fn sendSettings(self: *Http2Transport) !void {
        // Empty SETTINGS frame (using defaults)
        const settings_frame = Http2Frame{
            .length = 0,
            .frame_type = .settings,
            .flags = 0,
            .stream_id = 0,
            .payload = "",
        };

        const frame_data = try settings_frame.encode(self.allocator);
        defer self.allocator.free(frame_data);

        try self.tcp_client.send(frame_data);
        self.settings_sent = true;
    }

    fn sendGoaway(self: *Http2Transport) !void {
        // Simple GOAWAY frame
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 0, .big); // Last stream ID
        std.mem.writeInt(u32, payload[4..8], 0, .big); // Error code (NO_ERROR)

        const goaway_frame = Http2Frame{
            .length = 8,
            .frame_type = .goaway,
            .flags = 0,
            .stream_id = 0,
            .payload = &payload,
        };

        const frame_data = try goaway_frame.encode(self.allocator);
        defer self.allocator.free(frame_data);

        try self.tcp_client.send(frame_data);
    }

    fn sendGrpcHeaders(self: *Http2Transport, stream_id: u31, route: []const u8, content_length: usize) !void {
        // Simplified gRPC headers (would normally use HPACK compression)
        var headers = std.ArrayList(u8).init(self.allocator);
        defer headers.deinit();

        // Build pseudo-headers and gRPC headers
        const headers_str = try std.fmt.allocPrint(self.allocator,
            \\:method POST
            \\:path {s}
            \\:scheme https
            \\content-type application/grpc+proto
            \\grpc-encoding identity
            \\content-length {d}
            \\
        , .{ route, content_length + 5 }); // +5 for gRPC frame header
        defer self.allocator.free(headers_str);

        try headers.appendSlice(headers_str);

        const headers_frame = Http2Frame{
            .length = @intCast(headers.items.len),
            .frame_type = .headers,
            .flags = 0x4, // END_HEADERS
            .stream_id = stream_id,
            .payload = headers.items,
        };

        const frame_data = try headers_frame.encode(self.allocator);
        defer self.allocator.free(frame_data);

        try self.tcp_client.send(frame_data);
    }

    fn sendData(self: *Http2Transport, stream_id: u31, data: []const u8, end_stream: bool) !void {
        // gRPC frame format: [compressed_flag][message_length][message]
        var grpc_frame = std.ArrayList(u8).init(self.allocator);
        defer grpc_frame.deinit();

        try grpc_frame.append(0); // Not compressed
        try grpc_frame.appendSlice(std.mem.asBytes(&std.mem.nativeToBig(u32, @as(u32, @intCast(data.len)))));
        try grpc_frame.appendSlice(data);

        const flags: u8 = if (end_stream) 0x1 else 0x0; // END_STREAM

        const data_frame = Http2Frame{
            .length = @intCast(grpc_frame.items.len),
            .frame_type = .data,
            .flags = flags,
            .stream_id = stream_id,
            .payload = grpc_frame.items,
        };

        const frame_data = try data_frame.encode(self.allocator);
        defer self.allocator.free(frame_data);

        try self.tcp_client.send(frame_data);
    }

    fn recvFrame(self: *Http2Transport) !Http2Frame {
        // Read frame header (9 bytes)
        var header: [9]u8 = undefined;
        _ = try self.tcp_client.recv(&header);

        const length = std.mem.readInt(u24, header[0..3], .big);

        // Read payload
        const payload = try self.allocator.alloc(u8, length);
        _ = try self.tcp_client.recv(payload);

        // Combine header and payload
        var complete_frame = try self.allocator.alloc(u8, 9 + length);
        defer self.allocator.free(complete_frame);

        std.mem.copyForwards(u8, complete_frame[0..9], &header);
        std.mem.copyForwards(u8, complete_frame[9..], payload);

        return Http2Frame.parse(complete_frame);
    }

    fn readGrpcResponse(self: *Http2Transport, stream_id: u31) ![]u8 {
        var response_data = std.ArrayList(u8).init(self.allocator);
        defer response_data.deinit();

        while (self.connected) {
            const frame = try self.recvFrame();

            if (frame.stream_id != stream_id) continue;

            switch (frame.frame_type) {
                .data => {
                    if (self.parseGrpcMessage(frame.payload)) |message| {
                        try response_data.appendSlice(message);
                    } else |_| {}

                    if ((frame.flags & 0x1) != 0) { // END_STREAM
                        break;
                    }
                },
                .headers => {
                    if ((frame.flags & 0x1) != 0) { // END_STREAM
                        break;
                    }
                },
                .rst_stream => {
                    return Http2Error.StreamClosed;
                },
                else => {},
            }
        }

        return response_data.toOwnedSlice();
    }

    fn parseGrpcMessage(self: *Http2Transport, grpc_frame: []const u8) ![]const u8 {
        if (grpc_frame.len < 5) return Http2Error.InvalidFrame;

        // Skip compressed flag (1 byte) and read message length (4 bytes)
        const message_len = std.mem.readInt(u32, grpc_frame[1..5], .big);

        if (grpc_frame.len < 5 + message_len) return Http2Error.InvalidFrame;

        const message = grpc_frame[5..5 + message_len];
        return try self.allocator.dupe(u8, message);
    }

    fn getNextStreamId(self: *Http2Transport) u31 {
        const id = self.next_stream_id;
        self.next_stream_id += 2; // Client streams are odd
        return id;
    }
};