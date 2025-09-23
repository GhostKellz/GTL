const std = @import("std");

pub const AuthError = error{
    InvalidToken,
    TokenExpired,
    InsufficientScope,
    MalformedToken,
};

pub const TokenScope = enum {
    @"chat:read",
    @"chat:write",
    @"session:read",
    @"session:write",
    @"session:admin",
    @"tools:execute",
};

pub const GhostToken = struct {
    sub: []const u8, // user ID
    iss: []const u8, // issuer
    aud: []const u8, // audience (should be "gtl")
    exp: i64, // expiry timestamp
    iat: i64, // issued at timestamp
    scopes: []TokenScope,
    raw: []const u8, // original token string
    allocator: std.mem.Allocator,

    pub fn deinit(self: *GhostToken) void {
        self.allocator.free(self.sub);
        self.allocator.free(self.iss);
        self.allocator.free(self.aud);
        self.allocator.free(self.scopes);
        self.allocator.free(self.raw);
    }

    pub fn isValid(self: GhostToken) bool {
        const now = std.time.timestamp();
        return now < self.exp and std.mem.eql(u8, self.aud, "gtl");
    }

    pub fn hasScope(self: GhostToken, scope: TokenScope) bool {
        for (self.scopes) |s| {
            if (s == scope) return true;
        }
        return false;
    }
};

pub const AuthValidator = struct {
    allocator: std.mem.Allocator,
    // In production, this would include JWT signing keys, etc.

    pub fn init(allocator: std.mem.Allocator) AuthValidator {
        return AuthValidator{
            .allocator = allocator,
        };
    }

    pub fn validateToken(self: *AuthValidator, token_str: []const u8) !GhostToken {
        // TODO: Implement proper JWT validation
        // For MVP, we'll do basic validation

        if (token_str.len == 0) {
            return AuthError.InvalidToken;
        }

        // Mock token parsing for MVP
        const now = std.time.timestamp();

        return GhostToken{
            .sub = try self.allocator.dupe(u8, "user123"),
            .iss = try self.allocator.dupe(u8, "ghostauth.example.com"),
            .aud = try self.allocator.dupe(u8, "gtl"),
            .exp = now + 3600, // 1 hour from now
            .iat = now,
            .scopes = try self.allocator.dupe(TokenScope, &[_]TokenScope{ .@"chat:read", .@"chat:write" }),
            .raw = try self.allocator.dupe(u8, token_str),
            .allocator = self.allocator,
        };
    }

    pub fn requireScope(token: GhostToken, scope: TokenScope) !void {
        if (!token.hasScope(scope)) {
            return AuthError.InsufficientScope;
        }
    }
};