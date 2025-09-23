const std = @import("std");

// MVP³ - Ghost Transport Layer
// Literally just: ask AI, get answer

pub fn ask(allocator: std.mem.Allocator, question: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "Ghost AI says: {s}", .{question});
}

pub fn stream(question: []const u8, callback: fn([]const u8) void) void {
    _ = question;
    callback("Ghost");
    callback(" AI");
    callback(" works!");
}

test "mvp cubed" {
    const allocator = std.testing.allocator;

    const answer = try ask(allocator, "Hello?");
    defer allocator.free(answer);

    try std.testing.expect(answer.len > 0);
}