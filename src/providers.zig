const std = @import("std");
const Events = @import("events.zig");
const Transport = @import("transport.zig");
const tcp = @import("tcp.zig");

// GTL Provider Abstraction - The Universal AI Interface
// This is the foundation for making GTL the standard AI protocol

pub const ProviderType = enum {
    openai,
    anthropic,
    google,
    ollama,
    azure_openai,
    huggingface,
    replicate,
    custom,
};

pub const ModelCapabilities = struct {
    max_tokens: u32,
    supports_streaming: bool,
    supports_functions: bool,
    supports_vision: bool,
    supports_json_mode: bool,
    context_window: u32,
    cost_per_1k_input: f64,
    cost_per_1k_output: f64,
};

pub const ProviderConfig = struct {
    provider_type: ProviderType,
    api_key: ?[]const u8,
    base_url: []const u8,
    model: []const u8,
    capabilities: ModelCapabilities,
    timeout_ms: u32 = 30000,
    retry_attempts: u8 = 3,
};

pub const CompletionRequest = struct {
    messages: []Message,
    model: []const u8,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    stream: bool = false,
    tools: ?[]Tool = null,
    response_format: ?ResponseFormat = null,
};

pub const Message = struct {
    role: MessageRole,
    content: []const u8,
    name: ?[]const u8 = null,
    tool_calls: ?[]ToolCall = null,
};

pub const MessageRole = enum {
    system,
    user,
    assistant,
    tool,
};

pub const Tool = struct {
    type: []const u8, // "function"
    function: FunctionDef,
};

pub const FunctionDef = struct {
    name: []const u8,
    description: []const u8,
    parameters: std.json.Value,
};

pub const ToolCall = struct {
    id: []const u8,
    type: []const u8,
    function: FunctionCall,
};

pub const FunctionCall = struct {
    name: []const u8,
    arguments: []const u8,
};

pub const ResponseFormat = struct {
    type: []const u8, // "json_object" or "text"
};

// Universal AI Provider Interface
pub const AIProvider = struct {
    config: ProviderConfig,
    transport: *Transport.Client,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: ProviderConfig, transport: *Transport.Client) AIProvider {
        return AIProvider{
            .config = config,
            .transport = transport,
            .allocator = allocator,
        };
    }

    pub fn complete(self: *AIProvider, request: CompletionRequest) ![]u8 {
        // Convert GTL request to provider-specific format
        const provider_request = try self.translateRequest(request);
        defer self.allocator.free(provider_request);

        // Make HTTP API call directly to provider
        const response = try self.makeHttpRequest(provider_request);
        defer self.allocator.free(response);

        // Convert provider response back to GTL format
        return self.translateResponse(response);
    }

    pub fn stream(self: *AIProvider, request: CompletionRequest, handler: Events.EventHandler) !void {
        // Convert request for streaming
        var streaming_request = request;
        streaming_request.stream = true;

        const provider_request = try self.translateRequest(streaming_request);
        defer self.allocator.free(provider_request);

        // Make streaming HTTP request to provider
        try self.makeStreamingHttpRequest(provider_request, handler);
    }

    fn makeHttpRequest(self: *AIProvider, request_body: []const u8) ![]u8 {
        // Parse the base URL to get host and port
        const url = try self.parseUrl(self.config.base_url);

        // Create TCP client for HTTP request
        var client = tcp.TcpClient.init(self.allocator);
        defer client.disconnect();

        try client.connect(url.host, url.port);

        // Build HTTP headers
        var headers = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer headers.deinit();

        if (self.config.api_key) |api_key| {
            switch (self.config.provider_type) {
                .openai, .azure_openai => {
                    try headers.appendSlice("Authorization: Bearer ");
                    try headers.appendSlice(api_key);
                    try headers.appendSlice("\r\n");
                },
                .anthropic => {
                    try headers.appendSlice("x-api-key: ");
                    try headers.appendSlice(api_key);
                    try headers.appendSlice("\r\n");
                    try headers.appendSlice("anthropic-version: 2023-06-01\r\n");
                },
                .google => {
                    try headers.appendSlice("Authorization: Bearer ");
                    try headers.appendSlice(api_key);
                    try headers.appendSlice("\r\n");
                },
                else => {
                    try headers.appendSlice("Authorization: Bearer ");
                    try headers.appendSlice(api_key);
                    try headers.appendSlice("\r\n");
                },
            }
        }

        // Send HTTP request with provider-specific headers
        try client.sendHttpRequestWithHeaders("POST", self.getApiEndpoint(), url.host, request_body, headers.items);

        // Receive response
        const response = try client.recvHttpResponse(self.allocator);
        defer response.deinit();

        if (response.status_code >= 400) {
            return error.ApiError;
        }

        return self.allocator.dupe(u8, response.getBodyText());
    }

    fn makeStreamingHttpRequest(self: *AIProvider, request_body: []const u8, handler: Events.EventHandler) !void {
        // Similar to makeHttpRequest but handles streaming responses
        const url = try self.parseUrl(self.config.base_url);

        var client = tcp.TcpClient.init(self.allocator);
        defer client.disconnect();

        try client.connect(url.host, url.port);

        // Build headers for streaming
        var headers = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer headers.deinit();

        if (self.config.api_key) |api_key| {
            switch (self.config.provider_type) {
                .openai, .azure_openai => {
                    try headers.appendSlice("Authorization: Bearer ");
                    try headers.appendSlice(api_key);
                    try headers.appendSlice("\r\n");
                },
                .anthropic => {
                    try headers.appendSlice("x-api-key: ");
                    try headers.appendSlice(api_key);
                    try headers.appendSlice("\r\n");
                    try headers.appendSlice("anthropic-version: 2023-06-01\r\n");
                },
                .google => {
                    try headers.appendSlice("Authorization: Bearer ");
                    try headers.appendSlice(api_key);
                    try headers.appendSlice("\r\n");
                },
                else => {
                    try headers.appendSlice("Authorization: Bearer ");
                    try headers.appendSlice(api_key);
                    try headers.appendSlice("\r\n");
                },
            }
        }

        // Add streaming-specific headers
        try headers.appendSlice("Accept: text/event-stream\r\n");
        try headers.appendSlice("Cache-Control: no-cache\r\n");

        // Send request with streaming headers
        try client.sendHttpRequestWithHeaders("POST", self.getApiEndpoint(), url.host, request_body, headers.items);

        // Handle streaming response
        var buffer: [4096]u8 = undefined;
        while (true) {
            const bytes_read = client.recv(&buffer) catch |err| {
                if (err == error.ReceiveFailed) break;
                return err;
            };

            if (bytes_read == 0) break;

            // Parse SSE events and convert to GTL events
            const chunk = buffer[0..bytes_read];
            try self.parseStreamingChunk(chunk, handler);
        }

        // Send completion event
        handler(Events.GTLEvent{ .done = {} });
    }

    fn parseStreamingChunk(self: *AIProvider, chunk: []const u8, handler: Events.EventHandler) !void {
        // Parse streaming response chunks (SSE format)
        var lines = std.mem.splitSequence(u8, chunk, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "data: ")) {
                const data = line[6..];
                if (std.mem.eql(u8, data, "[DONE]")) {
                    return;
                }

                // Parse JSON and extract text
                if (self.extractTokenFromJson(data)) |token| {
                    handler(Events.GTLEvent{ .token = .{ .text = token } });
                } else |_| {
                    // Ignore parse errors in streaming
                }
            }
        }
    }

    fn extractTokenFromJson(self: *AIProvider, json_data: []const u8) ![]const u8 {
        // Simple JSON parsing to extract token text
        // This is a simplified implementation - in production, use a proper JSON parser
        _ = self;

        if (std.mem.indexOf(u8, json_data, "\"content\":\"")) |start| {
            const content_start = start + 11;
            if (std.mem.indexOf(u8, json_data[content_start..], "\"")) |end| {
                return json_data[content_start..content_start + end];
            }
        }

        return error.NoToken;
    }

    const UrlParts = struct {
        host: []const u8,
        port: u16,
        path: []const u8,
    };

    fn parseUrl(self: *AIProvider, url: []const u8) !UrlParts {
        // Simple URL parsing for https://host:port/path format
        var remaining = url;

        // Skip protocol
        if (std.mem.startsWith(u8, remaining, "https://")) {
            remaining = remaining[8..];
        } else if (std.mem.startsWith(u8, remaining, "http://")) {
            remaining = remaining[7..];
        }

        // Find host and port
        var host: []const u8 = remaining;
        var port: u16 = 443; // Default HTTPS port

        if (std.mem.indexOf(u8, remaining, ":")) |colon_pos| {
            host = remaining[0..colon_pos];

            const port_start = colon_pos + 1;
            if (std.mem.indexOf(u8, remaining[port_start..], "/")) |slash_pos| {
                const port_str = remaining[port_start..port_start + slash_pos];
                port = std.fmt.parseInt(u16, port_str, 10) catch 443;
            } else {
                const port_str = remaining[port_start..];
                port = std.fmt.parseInt(u16, port_str, 10) catch 443;
            }
        } else if (std.mem.indexOf(u8, remaining, "/")) |slash_pos| {
            host = remaining[0..slash_pos];
        }

        return UrlParts{
            .host = try self.allocator.dupe(u8, host),
            .port = port,
            .path = "/",
        };
    }

    fn translateRequest(self: *AIProvider, request: CompletionRequest) ![]u8 {
        switch (self.config.provider_type) {
            .openai, .azure_openai => return self.translateToOpenAI(request),
            .anthropic => return self.translateToClaude(request),
            .google => return self.translateToGemini(request),
            .ollama => return self.translateToOllama(request),
            .custom => return self.translateToCustom(request),
            else => return error.UnsupportedProvider,
        }
    }

    fn translateResponse(self: *AIProvider, response: []const u8) ![]u8 {
        switch (self.config.provider_type) {
            .openai, .azure_openai => return self.translateFromOpenAI(response),
            .anthropic => return self.translateFromClaude(response),
            .google => return self.translateFromGemini(response),
            .ollama => return self.translateFromOllama(response),
            .custom => return self.translateFromCustom(response),
            else => return error.UnsupportedProvider,
        }
    }

    fn translateStreamEvent(self: *AIProvider, event: Events.GTLEvent) !Events.GTLEvent {
        // Provider-specific streaming event translation
        _ = self;
        return event; // Simplified for now
    }

    fn getApiEndpoint(self: *AIProvider) []const u8 {
        switch (self.config.provider_type) {
            .openai => return "/v1/chat/completions",
            .anthropic => return "/v1/messages",
            .google => return "/v1/models/generate",
            .ollama => return "/api/chat",
            .azure_openai => return "/openai/deployments/{deployment}/chat/completions",
            else => return "/chat/completions",
        }
    }

    fn getStreamEndpoint(self: *AIProvider) []const u8 {
        return self.getApiEndpoint(); // Same endpoint, different params
    }

    // OpenAI Translation
    fn translateToOpenAI(self: *AIProvider, request: CompletionRequest) ![]u8 {
        // Build OpenAI-compatible JSON per official API spec
        var json = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("{\"model\":\"");
        try json.appendSlice(request.model);
        try json.appendSlice("\",\"messages\":[");

        // Format messages according to OpenAI ChatCompletionRequestMessage spec
        for (request.messages, 0..) |msg, i| {
            if (i > 0) try json.appendSlice(",");
            try json.appendSlice("{\"role\":\"");
            try json.appendSlice(@tagName(msg.role));
            try json.appendSlice("\",\"content\":\"");
            try json.appendSlice(msg.content);
            try json.appendSlice("\"}");
        }

        try json.appendSlice("],\"stream\":");
        try json.appendSlice(if (request.stream) "true" else "false");

        if (request.max_tokens) |max_tokens| {
            const max_tokens_str = try std.fmt.allocPrint(self.allocator, ",\"max_completion_tokens\":{d}", .{max_tokens});
            defer self.allocator.free(max_tokens_str);
            try json.appendSlice(max_tokens_str);
        }

        if (request.temperature) |temp| {
            const temp_str = try std.fmt.allocPrint(self.allocator, ",\"temperature\":{d}", .{temp});
            defer self.allocator.free(temp_str);
            try json.appendSlice(temp_str);
        }

        // Add tools if present
        if (request.tools) |tools| {
            try json.appendSlice(",\"tools\":[");
            for (tools, 0..) |tool, i| {
                if (i > 0) try json.appendSlice(",");
                try json.appendSlice("{\"type\":\"");
                try json.appendSlice(tool.type);
                try json.appendSlice("\",\"function\":{\"name\":\"");
                try json.appendSlice(tool.function.name);
                try json.appendSlice("\",\"description\":\"");
                try json.appendSlice(tool.function.description);
                try json.appendSlice("\"}}");
            }
            try json.appendSlice("]");
        }

        try json.appendSlice("}");
        return try json.toOwnedSlice();
    }

    fn translateFromOpenAI(self: *AIProvider, response: []const u8) ![]u8 {
        // Parse OpenAI response and extract content
        // This is a simplified JSON parser - in production, use a proper JSON library
        if (std.mem.indexOf(u8, response, "\"content\":\"")) |start| {
            const content_start = start + 11;
            if (std.mem.indexOf(u8, response[content_start..], "\"")) |end| {
                const content = response[content_start..content_start + end];

                // Build GTL-formatted response
                return std.fmt.allocPrint(self.allocator,
                    \\{{"provider":"openai","content":"{s}","usage":{{"tokens":100}}}}
                , .{content});
            }
        }

        // Fallback for responses without content field
        return std.fmt.allocPrint(self.allocator,
            \\{{"provider":"openai","content":"Error parsing response","error":"{s}"}}
        , .{response});
    }

    // Claude Translation
    fn translateToClaude(self: *AIProvider, request: CompletionRequest) ![]u8 {
        // Build Claude-compatible JSON per Anthropic API spec
        var json = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("{\"model\":\"");
        try json.appendSlice(request.model);
        try json.appendSlice("\",\"max_tokens\":");

        const max_tokens_str = try std.fmt.allocPrint(self.allocator, "{d}", .{request.max_tokens orelse 4096});
        defer self.allocator.free(max_tokens_str);
        try json.appendSlice(max_tokens_str);

        try json.appendSlice(",\"messages\":[");

        // Format messages for Claude (system messages are handled differently)
        var system_content: ?[]const u8 = null;
        var message_count: usize = 0;

        for (request.messages) |msg| {
            if (msg.role == .system) {
                system_content = msg.content;
                continue;
            }

            if (message_count > 0) try json.appendSlice(",");
            try json.appendSlice("{\"role\":\"");

            // Claude uses "user" and "assistant" roles
            const role_str = switch (msg.role) {
                .user => "user",
                .assistant => "assistant",
                .system => "user", // Fallback, shouldn't happen
                .tool => "user", // Convert tool messages to user messages
            };
            try json.appendSlice(role_str);
            try json.appendSlice("\",\"content\":\"");
            try json.appendSlice(msg.content);
            try json.appendSlice("\"}");
            message_count += 1;
        }

        try json.appendSlice("]");

        // Add system message if present
        if (system_content) |system| {
            try json.appendSlice(",\"system\":\"");
            try json.appendSlice(system);
            try json.appendSlice("\"");
        }

        if (request.temperature) |temp| {
            const temp_str = try std.fmt.allocPrint(self.allocator, ",\"temperature\":{d}", .{temp});
            defer self.allocator.free(temp_str);
            try json.appendSlice(temp_str);
        }

        if (request.stream) {
            try json.appendSlice(",\"stream\":true");
        }

        try json.appendSlice("}");
        return try json.toOwnedSlice();
    }

    fn translateFromClaude(self: *AIProvider, response: []const u8) ![]u8 {
        // Parse Claude response and extract content
        // Claude returns content in "content" array with "text" field
        if (std.mem.indexOf(u8, response, "\"text\":\"")) |start| {
            const content_start = start + 8;
            if (std.mem.indexOf(u8, response[content_start..], "\"")) |end| {
                const content = response[content_start..content_start + end];

                // Build GTL-formatted response
                return std.fmt.allocPrint(self.allocator,
                    \\{{"provider":"claude","content":"{s}","usage":{{"tokens":100}}}}
                , .{content});
            }
        }

        // Fallback for responses without text field
        return std.fmt.allocPrint(self.allocator,
            \\{{"provider":"claude","content":"Error parsing response","error":"{s}"}}
        , .{response});
    }

    // Gemini Translation
    fn translateToGemini(self: *AIProvider, request: CompletionRequest) ![]u8 {
        // Build Gemini-compatible JSON per Google AI API spec
        var json = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("{\"contents\":[");

        // Format messages for Gemini
        var message_count: usize = 0;
        for (request.messages) |msg| {
            // Skip system messages for now (Gemini handles them differently)
            if (msg.role == .system) continue;

            if (message_count > 0) try json.appendSlice(",");
            try json.appendSlice("{\"parts\":[{\"text\":\"");
            try json.appendSlice(msg.content);
            try json.appendSlice("\"}],\"role\":\"");

            // Gemini uses "user" and "model" roles
            const role_str = switch (msg.role) {
                .user => "user",
                .assistant => "model",
                .system => "user", // Fallback
                .tool => "user", // Convert tool messages
            };
            try json.appendSlice(role_str);
            try json.appendSlice("\"}");
            message_count += 1;
        }

        try json.appendSlice("],\"generationConfig\":{");

        if (request.max_tokens) |max_tokens| {
            const max_tokens_str = try std.fmt.allocPrint(self.allocator, "\"maxOutputTokens\":{d}", .{max_tokens});
            defer self.allocator.free(max_tokens_str);
            try json.appendSlice(max_tokens_str);
        }

        if (request.temperature) |temp| {
            const temp_str = try std.fmt.allocPrint(self.allocator, ",\"temperature\":{d}", .{temp});
            defer self.allocator.free(temp_str);
            try json.appendSlice(temp_str);
        }

        try json.appendSlice("}");

        // Add stream parameter if needed (Gemini uses a different endpoint for streaming)
        if (request.stream) {
            try json.appendSlice(",\"stream\":true");
        }

        try json.appendSlice("}");
        return try json.toOwnedSlice();
    }

    fn translateFromGemini(self: *AIProvider, response: []const u8) ![]u8 {
        // Parse Gemini response and extract content
        // Gemini returns content in "candidates" array with "content.parts[0].text"
        if (std.mem.indexOf(u8, response, "\"text\":\"")) |start| {
            const content_start = start + 8;
            if (std.mem.indexOf(u8, response[content_start..], "\"")) |end| {
                const content = response[content_start..content_start + end];

                // Build GTL-formatted response
                return std.fmt.allocPrint(self.allocator,
                    \\{{"provider":"gemini","content":"{s}","usage":{{"tokens":100}}}}
                , .{content});
            }
        }

        // Fallback for responses without text field
        return std.fmt.allocPrint(self.allocator,
            \\{{"provider":"gemini","content":"Error parsing response","error":"{s}"}}
        , .{response});
    }

    // Ollama Translation
    fn translateToOllama(self: *AIProvider, request: CompletionRequest) ![]u8 {
        // Build Ollama-compatible JSON for chat endpoint
        var json = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("{\"model\":\"");
        try json.appendSlice(request.model);
        try json.appendSlice("\",\"messages\":[");

        // Format messages for Ollama (supports chat format)
        for (request.messages, 0..) |msg, i| {
            if (i > 0) try json.appendSlice(",");
            try json.appendSlice("{\"role\":\"");

            // Ollama supports system, user, assistant roles
            const role_str = switch (msg.role) {
                .system => "system",
                .user => "user",
                .assistant => "assistant",
                .tool => "user", // Convert tool messages to user messages
            };
            try json.appendSlice(role_str);
            try json.appendSlice("\",\"content\":\"");
            try json.appendSlice(msg.content);
            try json.appendSlice("\"}");
        }

        try json.appendSlice("]");

        if (request.stream) {
            try json.appendSlice(",\"stream\":true");
        }

        // Add generation options
        try json.appendSlice(",\"options\":{");

        if (request.temperature) |temp| {
            const temp_str = try std.fmt.allocPrint(self.allocator, "\"temperature\":{d}", .{temp});
            defer self.allocator.free(temp_str);
            try json.appendSlice(temp_str);
        }

        if (request.max_tokens) |max_tokens| {
            const max_tokens_str = try std.fmt.allocPrint(self.allocator, ",\"num_predict\":{d}", .{max_tokens});
            defer self.allocator.free(max_tokens_str);
            try json.appendSlice(max_tokens_str);
        }

        try json.appendSlice("}");
        try json.appendSlice("}");
        return try json.toOwnedSlice();
    }

    fn translateFromOllama(self: *AIProvider, response: []const u8) ![]u8 {
        // Parse Ollama response and extract content
        // Ollama returns content in "message.content" field for chat endpoint
        if (std.mem.indexOf(u8, response, "\"content\":\"")) |start| {
            const content_start = start + 11;
            if (std.mem.indexOf(u8, response[content_start..], "\"")) |end| {
                const content = response[content_start..content_start + end];

                // Build GTL-formatted response
                return std.fmt.allocPrint(self.allocator,
                    \\{{"provider":"ollama","content":"{s}","usage":{{"tokens":100}}}}
                , .{content});
            }
        }

        // Fallback for responses without content field
        return std.fmt.allocPrint(self.allocator,
            \\{{"provider":"ollama","content":"Error parsing response","error":"{s}"}}
        , .{response});
    }

    // Custom Provider Translation
    fn translateToCustom(self: *AIProvider, request: CompletionRequest) ![]u8 {
        // Generic JSON format that most APIs can handle
        return std.fmt.allocPrint(self.allocator,
            \\{{"model":"{s}","messages":[{s}],"max_tokens":{d},"stream":{s}}}
        , .{
            request.model,
            try self.formatMessages(request.messages),
            request.max_tokens orelse 1000,
            if (request.stream) "true" else "false",
        });
    }

    fn translateFromCustom(self: *AIProvider, response: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{{"provider":"custom","content":"{s}","usage":{{"tokens":100}}}}
        , .{response});
    }

    // Helper functions for message formatting
    fn formatMessages(self: *AIProvider, messages: []Message) ![]u8 {
        var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer result.deinit();

        for (messages, 0..) |msg, i| {
            if (i > 0) try result.appendSlice(",");

            const formatted = try std.fmt.allocPrint(self.allocator,
                \\{{"role":"{s}","content":"{s}"}}
            , .{ @tagName(msg.role), msg.content });
            defer self.allocator.free(formatted);

            try result.appendSlice(formatted);
        }

        return try result.toOwnedSlice();
    }

    fn formatGeminiMessages(self: *AIProvider, messages: []Message) ![]u8 {
        // Gemini uses "contents" format
        return self.formatMessages(messages); // Simplified for now
    }

    fn formatOllamaPrompt(self: *AIProvider, messages: []Message) ![]u8 {
        // Convert messages to single prompt for Ollama
        var result = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer result.deinit();

        for (messages) |msg| {
            try result.appendSlice(msg.content);
            try result.appendSlice("\n");
        }

        return try result.toOwnedSlice();
    }
};

// Provider Factory for easy instantiation
pub const ProviderFactory = struct {
    allocator: std.mem.Allocator,
    transport: *Transport.Client,

    pub fn init(allocator: std.mem.Allocator, transport: *Transport.Client) ProviderFactory {
        return ProviderFactory{
            .allocator = allocator,
            .transport = transport,
        };
    }

    pub fn createOpenAI(self: *ProviderFactory, api_key: []const u8, model: []const u8) AIProvider {
        const config = ProviderConfig{
            .provider_type = .openai,
            .api_key = api_key,
            .base_url = "https://api.openai.com",
            .model = model,
            .capabilities = ModelCapabilities{
                .max_tokens = 4096,
                .supports_streaming = true,
                .supports_functions = true,
                .supports_vision = true,
                .supports_json_mode = true,
                .context_window = 128000,
                .cost_per_1k_input = 0.01,
                .cost_per_1k_output = 0.03,
            },
        };

        return AIProvider.init(self.allocator, config, self.transport);
    }

    pub fn createClaude(self: *ProviderFactory, api_key: []const u8, model: []const u8) AIProvider {
        const config = ProviderConfig{
            .provider_type = .anthropic,
            .api_key = api_key,
            .base_url = "https://api.anthropic.com",
            .model = model,
            .capabilities = ModelCapabilities{
                .max_tokens = 4096,
                .supports_streaming = true,
                .supports_functions = true,
                .supports_vision = true,
                .supports_json_mode = false,
                .context_window = 200000,
                .cost_per_1k_input = 0.015,
                .cost_per_1k_output = 0.075,
            },
        };

        return AIProvider.init(self.allocator, config, self.transport);
    }

    pub fn createGemini(self: *ProviderFactory, api_key: []const u8, model: []const u8) AIProvider {
        const config = ProviderConfig{
            .provider_type = .google,
            .api_key = api_key,
            .base_url = "https://generativelanguage.googleapis.com",
            .model = model,
            .capabilities = ModelCapabilities{
                .max_tokens = 2048,
                .supports_streaming = true,
                .supports_functions = true,
                .supports_vision = true,
                .supports_json_mode = false,
                .context_window = 128000,
                .cost_per_1k_input = 0.0005,
                .cost_per_1k_output = 0.0015,
            },
        };

        return AIProvider.init(self.allocator, config, self.transport);
    }

    pub fn createOllama(self: *ProviderFactory, base_url: []const u8, model: []const u8) AIProvider {
        const config = ProviderConfig{
            .provider_type = .ollama,
            .api_key = null,
            .base_url = base_url,
            .model = model,
            .capabilities = ModelCapabilities{
                .max_tokens = 2048,
                .supports_streaming = true,
                .supports_functions = false,
                .supports_vision = false,
                .supports_json_mode = false,
                .context_window = 4096,
                .cost_per_1k_input = 0.0, // Free/self-hosted
                .cost_per_1k_output = 0.0,
            },
        };

        return AIProvider.init(self.allocator, config, self.transport);
    }

    pub fn createCustom(self: *ProviderFactory, base_url: []const u8, api_key: ?[]const u8, model: []const u8) AIProvider {
        const config = ProviderConfig{
            .provider_type = .custom,
            .api_key = api_key,
            .base_url = base_url,
            .model = model,
            .capabilities = ModelCapabilities{
                .max_tokens = 2048,
                .supports_streaming = true,
                .supports_functions = false,
                .supports_vision = false,
                .supports_json_mode = false,
                .context_window = 4096,
                .cost_per_1k_input = 0.0,
                .cost_per_1k_output = 0.0,
            },
        };

        return AIProvider.init(self.allocator, config, self.transport);
    }
};