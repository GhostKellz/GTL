const std = @import("std");

pub const EventType = enum {
    status,
    token,
    patch,
    usage,
    @"error",
    done,
};

pub const StatusState = enum {
    connecting,
    streaming,
    paused,
    completed,
    failed,
};

pub const PatchOp = union(enum) {
    Replace: struct {
        range: Range,
        text: []const u8,
    },
    Insert: struct {
        range: Range,
        text: []const u8,
    },
    Delete: struct {
        range: Range,
    },
};

pub const Range = struct {
    sl: u32, // start line
    sc: u32, // start column
    el: u32, // end line
    ec: u32, // end column
};

pub const GTLEvent = union(EventType) {
    status: struct {
        state: StatusState,
    },
    token: struct {
        text: []const u8,
    },
    patch: struct {
        op: PatchOp,
        rev: u32,
    },
    usage: struct {
        tokens_in: u32,
        tokens_out: u32,
        cost: f64,
    },
    @"error": struct {
        code: []const u8,
        message: []const u8,
    },
    done: void,
};

pub const GTLFrame = struct {
    sid: []const u8,
    event: GTLEvent,

    pub fn toJson(self: GTLFrame, allocator: std.mem.Allocator) ![]u8 {
        // Simplified JSON serialization for MVP
        return std.fmt.allocPrint(allocator, "{{\"sid\":\"{s}\",\"type\":\"token\",\"text\":\"hello\"}}", .{self.sid});
    }

    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !GTLFrame {
        return std.json.parseFromSlice(GTLFrame, allocator, json_str, .{});
    }
};

pub const EventHandler = *const fn (event: GTLEvent) void;