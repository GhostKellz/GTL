const std = @import("std");

pub const GTLRuntime = struct {
    allocator: std.mem.Allocator,
    epoll_fd: i32,
    running: bool,
    timers: std.ArrayList(Timer),
    channels: std.ArrayList(*Channel),

    const MAX_EVENTS = 64;

    pub fn init(allocator: std.mem.Allocator) !GTLRuntime {
        const epoll_fd = std.os.linux.epoll_create1(0);
        return GTLRuntime{
            .allocator = allocator,
            .epoll_fd = epoll_fd,
            .running = false,
            .timers = std.ArrayList(Timer).init(allocator),
            .channels = std.ArrayList(*Channel).init(allocator),
        };
    }

    pub fn deinit(self: *GTLRuntime) void {
        std.os.close(self.epoll_fd);
        self.timers.deinit();
        self.channels.deinit();
    }

    pub fn spawn(self: *GTLRuntime, comptime func: anytype, args: anytype) !void {
        _ = self;
        // For MVP: just run synchronously
        // TODO: Implement proper task spawning
        @call(.auto, func, args);
    }

    pub fn sleep(self: *GTLRuntime, duration_ms: u64) !void {
        _ = self;
        std.time.sleep(duration_ms * std.time.ns_per_ms);
    }

    pub fn run(self: *GTLRuntime) !void {
        self.running = true;

        while (self.running) {
            // Simple event loop for MVP
            // TODO: Implement proper epoll-based event handling
            std.time.sleep(10 * std.time.ns_per_ms); // 10ms tick

            // Process timers
            self.processTimers();
        }
    }

    pub fn stop(self: *GTLRuntime) void {
        self.running = false;
    }

    fn processTimers(self: *GTLRuntime) void {
        const now = std.time.milliTimestamp();

        var i: usize = 0;
        while (i < self.timers.items.len) {
            const timer = &self.timers.items[i];
            if (now >= timer.deadline) {
                // Timer fired
                timer.callback();
                _ = self.timers.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn setTimeout(self: *GTLRuntime, delay_ms: u64, callback: fn() void) !void {
        const deadline = std.time.milliTimestamp() + @as(i64, @intCast(delay_ms));
        try self.timers.append(Timer{
            .deadline = deadline,
            .callback = callback,
        });
    }
};

const Timer = struct {
    deadline: i64,
    callback: fn() void,
};

pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        items: std.ArrayList(T),
        allocator: std.mem.Allocator,
        capacity: usize,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) Self {
            return Self{
                .items = std.ArrayList(T).init(allocator),
                .allocator = allocator,
                .capacity = capacity,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn send(self: *Self, item: T) !void {
            if (self.items.items.len >= self.capacity) {
                return error.ChannelFull;
            }
            try self.items.append(item);
        }

        pub fn recv(self: *Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.orderedRemove(0);
        }

        pub fn len(self: *Self) usize {
            return self.items.items.len;
        }
    };
}