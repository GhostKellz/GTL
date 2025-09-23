const std = @import("std");
const Events = @import("events.zig");

pub const SessionId = []const u8;

pub const SessionState = enum {
    initializing,
    active,
    paused,
    completed,
    failed,
};

pub const Session = struct {
    id: SessionId,
    state: SessionState,
    model: []const u8,
    created_at: i64,
    last_activity: i64,
    revision: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, model: []const u8) !Session {
        const timestamp = std.time.timestamp();
        const id = try generateSessionId(allocator);

        return Session{
            .id = id,
            .state = .initializing,
            .model = try allocator.dupe(u8, model),
            .created_at = timestamp,
            .last_activity = timestamp,
            .revision = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Session) void {
        self.allocator.free(self.id);
        self.allocator.free(self.model);
    }

    pub fn updateActivity(self: *Session) void {
        self.last_activity = std.time.timestamp();
    }

    pub fn incrementRevision(self: *Session) void {
        self.revision += 1;
    }

    fn generateSessionId(allocator: std.mem.Allocator) ![]u8 {
        var buf: [16]u8 = undefined;
        std.crypto.random.bytes(&buf);

        var hex_buf: [32]u8 = undefined;
        for (buf, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_buf[i * 2 .. (i + 1) * 2], "{x:0>2}", .{byte}) catch unreachable;
        }

        return allocator.dupe(u8, &hex_buf);
    }
};

pub const SessionManager = struct {
    sessions: std.HashMap([]const u8, Session, SessionContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    const SessionContext = struct {
        pub fn hash(self: @This(), s: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    pub fn init(allocator: std.mem.Allocator) SessionManager {
        return SessionManager{
            .sessions = std.HashMap([]const u8, Session, SessionContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SessionManager) void {
        var iterator = self.sessions.iterator();
        while (iterator.next()) |entry| {
            var session = entry.value_ptr;
            session.deinit();
        }
        self.sessions.deinit();
    }

    pub fn createSession(self: *SessionManager, model: []const u8) !*Session {
        const session = try Session.init(self.allocator, model);
        try self.sessions.put(session.id, session);
        return self.sessions.getPtr(session.id).?;
    }

    pub fn getSession(self: *SessionManager, id: SessionId) ?*Session {
        return self.sessions.getPtr(id);
    }

    pub fn removeSession(self: *SessionManager, id: SessionId) void {
        if (self.sessions.fetchRemove(id)) |kv| {
            var session = kv.value;
            session.deinit();
        }
    }
};