const std = @import("std");

pub const TcpError = error{
    ConnectionFailed,
    SendFailed,
    ReceiveFailed,
    InvalidAddress,
    Timeout,
};

pub const TcpClient = struct {
    socket: std.net.Stream,
    allocator: std.mem.Allocator,
    connected: bool,

    pub fn init(allocator: std.mem.Allocator) TcpClient {
        return TcpClient{
            .socket = undefined,
            .allocator = allocator,
            .connected = false,
        };
    }

    pub fn connect(self: *TcpClient, host: []const u8, port: u16) !void {
        const address = std.net.Address.parseIp(host, port) catch blk: {
            // Try resolving hostname
            const addr_list = std.net.getAddressList(self.allocator, host, port) catch {
                return TcpError.InvalidAddress;
            };
            defer addr_list.deinit();

            if (addr_list.addrs.len == 0) return TcpError.InvalidAddress;
            break :blk addr_list.addrs[0];
        };

        self.socket = std.net.tcpConnectToAddress(address) catch {
            return TcpError.ConnectionFailed;
        };

        self.connected = true;
    }

    pub fn disconnect(self: *TcpClient) void {
        if (self.connected) {
            self.socket.close();
            self.connected = false;
        }
    }

    pub fn send(self: *TcpClient, data: []const u8) !void {
        if (!self.connected) return TcpError.ConnectionFailed;

        _ = self.socket.writeAll(data) catch {
            return TcpError.SendFailed;
        };
    }

    pub fn recv(self: *TcpClient, buffer: []u8) !usize {
        if (!self.connected) return TcpError.ConnectionFailed;

        return self.socket.read(buffer) catch {
            return TcpError.ReceiveFailed;
        };
    }

    pub fn recvLine(self: *TcpClient, buffer: []u8) ![]u8 {
        if (!self.connected) return TcpError.ConnectionFailed;

        var pos: usize = 0;
        while (pos < buffer.len - 1) {
            const bytes_read = self.socket.read(buffer[pos..pos+1]) catch {
                return TcpError.ReceiveFailed;
            };

            if (bytes_read == 0) break;

            if (buffer[pos] == '\n') {
                buffer[pos] = 0; // null terminate
                return buffer[0..pos];
            }

            pos += 1;
        }

        return buffer[0..pos];
    }

    pub fn sendHttpRequest(self: *TcpClient, method: []const u8, path: []const u8, host: []const u8, body: ?[]const u8) !void {
        return self.sendHttpRequestWithHeaders(method, path, host, body, null);
    }

    pub fn sendHttpRequestWithHeaders(self: *TcpClient, method: []const u8, path: []const u8, host: []const u8, body: ?[]const u8, extra_headers: ?[]const u8) !void {
        // Build HTTP request
        var request = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer request.deinit();

        try request.appendSlice(method);
        try request.appendSlice(" ");
        try request.appendSlice(path);
        try request.appendSlice(" HTTP/1.1\r\n");
        try request.appendSlice("Host: ");
        try request.appendSlice(host);
        try request.appendSlice("\r\n");
        try request.appendSlice("User-Agent: GTL/0.1\r\n");

        // Add extra headers if provided
        if (extra_headers) |headers| {
            try request.appendSlice(headers);
        }

        if (body) |b| {
            try request.appendSlice("Content-Length: ");
            const len_str = try std.fmt.allocPrint(self.allocator, "{d}", .{b.len});
            defer self.allocator.free(len_str);
            try request.appendSlice(len_str);
            try request.appendSlice("\r\n");
            try request.appendSlice("Content-Type: application/json\r\n");
        }

        try request.appendSlice("\r\n");

        if (body) |b| {
            try request.appendSlice(b);
        }

        try self.send(request.items);
    }

    pub fn recvHttpResponse(self: *TcpClient, allocator: std.mem.Allocator) !HttpResponse {
        var response = HttpResponse.init(allocator);

        // Read status line
        var status_buf: [256]u8 = undefined;
        const status_line = try self.recvLine(&status_buf);

        // Parse "HTTP/1.1 200 OK"
        var parts = std.mem.splitSequence(u8, status_line, " ");
        _ = parts.next(); // Skip HTTP version
        if (parts.next()) |status_code_str| {
            response.status_code = std.fmt.parseInt(u16, status_code_str, 10) catch 500;
        }

        // Read headers
        var header_buf: [1024]u8 = undefined;
        while (true) {
            const header_line = try self.recvLine(&header_buf);
            if (header_line.len == 0) break; // Empty line = end of headers

            if (std.mem.indexOf(u8, header_line, ": ")) |colon_pos| {
                const name = header_line[0..colon_pos];
                const value = header_line[colon_pos + 2..];

                if (std.mem.eql(u8, name, "Content-Length")) {
                    response.content_length = std.fmt.parseInt(usize, value, 10) catch 0;
                }
            }
        }

        // Read body if present
        if (response.content_length > 0) {
            response.body = try allocator.alloc(u8, response.content_length);
            var total_read: usize = 0;
            while (total_read < response.content_length) {
                const bytes_read = try self.recv(response.body.?[total_read..]);
                if (bytes_read == 0) break;
                total_read += bytes_read;
            }
        }

        return response;
    }
};

pub const HttpResponse = struct {
    status_code: u16,
    content_length: usize,
    body: ?[]u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HttpResponse {
        return HttpResponse{
            .status_code = 0,
            .content_length = 0,
            .body = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HttpResponse) void {
        if (self.body) |body| {
            self.allocator.free(body);
        }
    }

    pub fn getBodyText(self: HttpResponse) []const u8 {
        return self.body orelse "";
    }
};

pub const TcpServer = struct {
    socket: std.net.Server,
    allocator: std.mem.Allocator,
    running: bool,

    pub fn init(allocator: std.mem.Allocator) TcpServer {
        return TcpServer{
            .socket = undefined,
            .allocator = allocator,
            .running = false,
        };
    }

    pub fn listen(self: *TcpServer, host: []const u8, port: u16) !void {
        const address = std.net.Address.parseIp(host, port) catch {
            return TcpError.InvalidAddress;
        };

        self.socket = address.listen(.{}) catch {
            return TcpError.ConnectionFailed;
        };

        self.running = true;
    }

    pub fn accept(self: *TcpServer) !TcpClient {
        if (!self.running) return TcpError.ConnectionFailed;

        const connection = self.socket.accept() catch {
            return TcpError.ConnectionFailed;
        };

        return TcpClient{
            .socket = connection.stream,
            .allocator = self.allocator,
            .connected = true,
        };
    }

    pub fn stop(self: *TcpServer) void {
        if (self.running) {
            self.socket.deinit();
            self.running = false;
        }
    }
};