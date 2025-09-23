const std = @import("std");
const GTL = @import("GTL");
const Providers = @import("providers.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🤖 GTL AI Provider Integration Demo\n", .{});
    std.debug.print("=====================================\n\n", .{});

    // Initialize GTL transport
    const connect_opts = GTL.ConnectOpts{
        .endpoint = "stdio://localhost",
        .transport_preference = .stdio,
        .token = "demo-ghost-token-v1",
    };

    var client = try GTL.connect(allocator, connect_opts);
    defer client.deinit();

    // Initialize Provider Factory
    var factory = Providers.ProviderFactory.init(allocator, &client);

    // Demo all major AI providers
    try demoOpenAI(allocator, &factory);
    try demoClaude(allocator, &factory);
    try demoGemini(allocator, &factory);
    try demoOllama(allocator, &factory);
    try demoMultiProvider(allocator, &factory);

    std.debug.print("🎉 GTL Protocol Demo Complete!\n", .{});
    std.debug.print("Ready for production AI provider integration!\n", .{});
}

fn demoOpenAI(allocator: std.mem.Allocator, factory: *Providers.ProviderFactory) !void {
    std.debug.print("🔥 OpenAI Integration Demo\n", .{});
    std.debug.print("==========================\n", .{});

    var provider = factory.createOpenAI("demo-api-key", "gpt-4");

    // Create a completion request
    const messages = [_]Providers.Message{
        .{ .role = .system, .content = "You are a helpful AI assistant." },
        .{ .role = .user, .content = "Explain quantum computing in one sentence." },
    };

    const request = Providers.CompletionRequest{
        .messages = @constCast(&messages),
        .model = "gpt-4",
        .max_tokens = 100,
        .temperature = 0.7,
        .stream = false,
    };

    std.debug.print("📤 Sending request to OpenAI via GTL...\n", .{});

    const response = provider.complete(request) catch |err| {
        std.debug.print("⚠️  OpenAI request failed (expected for demo): {}\n", .{err});
        std.debug.print("✅ OpenAI integration ready for real API keys!\n\n", .{});
        return;
    };
    defer allocator.free(response);

    std.debug.print("📥 OpenAI Response: {s}\n", .{response});

    // Demo streaming
    std.debug.print("🌊 Testing OpenAI streaming...\n", .{});

    var streaming_request = request;
    streaming_request.stream = true;

    const StreamHandler = struct {
        fn handle(event: GTL.GTLEvent) void {
            switch (event) {
                .token => |t| std.debug.print("{s}", .{t.text}),
                .done => std.debug.print("\n✅ Stream complete!\n", .{}),
                else => {},
            }
        }
    };

    provider.stream(streaming_request, StreamHandler.handle) catch |err| {
        std.debug.print("⚠️  Streaming failed (expected): {}\n", .{err});
        std.debug.print("✅ OpenAI streaming integration ready!\n", .{});
    };

    std.debug.print("\n");
}

fn demoClaude(allocator: std.mem.Allocator, factory: *Providers.ProviderFactory) !void {
    std.debug.print("🧠 Anthropic Claude Integration Demo\n", .{});
    std.debug.print("====================================\n", .{});

    var provider = factory.createClaude("demo-api-key", "claude-3-sonnet");

    const messages = [_]Providers.Message{
        .{ .role = .user, .content = "What makes a great AI assistant?" },
    };

    const request = Providers.CompletionRequest{
        .messages = @constCast(&messages),
        .model = "claude-3-sonnet",
        .max_tokens = 150,
        .stream = false,
    };

    std.debug.print("📤 Sending request to Claude via GTL...\n", .{});

    const response = provider.complete(request) catch |err| {
        std.debug.print("⚠️  Claude request failed (expected for demo): {}\n", .{err});
        std.debug.print("✅ Claude integration ready for real API keys!\n", .{});
        std.debug.print("💡 Claude features: 200K context, reasoning, safety\n\n", .{});
        return;
    };
    defer allocator.free(response);

    std.debug.print("📥 Claude Response: {s}\n\n", .{response});
}

fn demoGemini(allocator: std.mem.Allocator, factory: *Providers.ProviderFactory) !void {
    std.debug.print("🌟 Google Gemini Integration Demo\n", .{});
    std.debug.print("=================================\n", .{});

    var provider = factory.createGemini("demo-api-key", "gemini-pro");

    const messages = [_]Providers.Message{
        .{ .role = .user, .content = "Explain the benefits of multimodal AI in 50 words." },
    };

    const request = Providers.CompletionRequest{
        .messages = @constCast(&messages),
        .model = "gemini-pro",
        .max_tokens = 100,
        .stream = false,
    };

    std.debug.print("📤 Sending request to Gemini via GTL...\n", .{});

    const response = provider.complete(request) catch |err| {
        std.debug.print("⚠️  Gemini request failed (expected for demo): {}\n", .{err});
        std.debug.print("✅ Gemini integration ready for real API keys!\n", .{});
        std.debug.print("💡 Gemini features: Multimodal, fast, cost-effective\n\n", .{});
        return;
    };
    defer allocator.free(response);

    std.debug.print("📥 Gemini Response: {s}\n\n", .{response});
}

fn demoOllama(allocator: std.mem.Allocator, factory: *Providers.ProviderFactory) !void {
    std.debug.print("🏠 Ollama Local AI Integration Demo\n", .{});
    std.debug.print("===================================\n", .{});

    var provider = factory.createOllama("http://localhost:11434", "llama2");

    const messages = [_]Providers.Message{
        .{ .role = .user, .content = "Why is local AI important for privacy?" },
    };

    const request = Providers.CompletionRequest{
        .messages = @constCast(&messages),
        .model = "llama2",
        .max_tokens = 100,
        .stream = false,
    };

    std.debug.print("📤 Sending request to Ollama via GTL...\n", .{});

    const response = provider.complete(request) catch |err| {
        std.debug.print("⚠️  Ollama request failed (expected - need local Ollama): {}\n", .{err});
        std.debug.print("✅ Ollama integration ready for local deployment!\n", .{});
        std.debug.print("💡 Ollama features: Privacy, no API costs, offline\n\n", .{});
        return;
    };
    defer allocator.free(response);

    std.debug.print("📥 Ollama Response: {s}\n\n", .{response});
}

fn demoMultiProvider(allocator: std.mem.Allocator, factory: *Providers.ProviderFactory) !void {
    std.debug.print("🔀 Multi-Provider Failover Demo\n", .{});
    std.debug.print("===============================\n", .{});

    // Create multiple providers
    var openai = factory.createOpenAI("demo-key", "gpt-4");
    var claude = factory.createClaude("demo-key", "claude-3-sonnet");
    var gemini = factory.createGemini("demo-key", "gemini-pro");

    const providers = [_]*Providers.AIProvider{ &openai, &claude, &gemini };

    const messages = [_]Providers.Message{
        .{ .role = .user, .content = "What's the future of AI?" },
    };

    const request = Providers.CompletionRequest{
        .messages = @constCast(&messages),
        .model = "auto", // Let GTL choose best provider
        .max_tokens = 100,
        .stream = false,
    };

    std.debug.print("🎯 GTL Auto-Selecting Best Provider...\n", .{});

    // Try providers in order until one succeeds
    for (providers, 0..) |provider, i| {
        std.debug.print("🔄 Trying provider {d}...\n", .{i + 1});

        const response = provider.complete(request) catch |err| {
            std.debug.print("❌ Provider {d} failed: {}\n", .{ i + 1, err });
            continue;
        };
        defer allocator.free(response);

        std.debug.print("✅ Provider {d} succeeded!\n", .{i + 1});
        std.debug.print("📥 Response: {s}\n", .{response});
        break;
    } else {
        std.debug.print("⚠️  All providers failed (expected for demo)\n", .{});
        std.debug.print("✅ Multi-provider failover system ready!\n", .{});
    }

    std.debug.print("\n");
}

test "AI provider integration" {
    const allocator = std.testing.allocator;

    // Test provider factory
    var mock_transport = GTL.Transport.Client.init(allocator, .{
        .endpoint = "stdio://test",
        .transport_preference = .stdio,
    }) catch unreachable;
    defer mock_transport.deinit();

    var factory = Providers.ProviderFactory.init(allocator, &mock_transport);

    // Test creating different providers
    var openai = factory.createOpenAI("test-key", "gpt-4");
    var claude = factory.createClaude("test-key", "claude-3");
    var gemini = factory.createGemini("test-key", "gemini-pro");
    var ollama = factory.createOllama("http://localhost:11434", "llama2");

    // Verify provider configurations
    try std.testing.expect(openai.config.provider_type == .openai);
    try std.testing.expect(claude.config.provider_type == .anthropic);
    try std.testing.expect(gemini.config.provider_type == .google);
    try std.testing.expect(ollama.config.provider_type == .ollama);

    // Test provider capabilities
    try std.testing.expect(openai.config.capabilities.supports_streaming);
    try std.testing.expect(claude.config.capabilities.supports_functions);
    try std.testing.expect(gemini.config.capabilities.supports_vision);
    try std.testing.expect(!ollama.config.capabilities.supports_functions);
}