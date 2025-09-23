const std = @import("std");
const GTL = @import("GTL");
const Providers = @import("providers.zig");
const Failover = @import("failover.zig");
const Metrics = @import("metrics.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("📊 GTL Comprehensive Logging & Metrics Demo\n", .{});
    std.debug.print("============================================\n\n", .{});

    // Initialize logging system
    var logger = try Metrics.Logger.init(allocator, .info, true, "gtl-metrics.log");
    defer logger.deinit();

    try logger.info("SYSTEM", "GTL metrics demo starting up", .{});

    // Initialize metrics collector
    var metrics_collector = Metrics.MetricsCollector.init(allocator, &logger, true);
    defer metrics_collector.deinit();

    // Initialize GTL transport
    const connect_opts = GTL.ConnectOpts{
        .endpoint = "stdio://localhost",
        .transport_preference = .stdio,
        .token = "demo-ghost-token-v1",
    };

    var client = try GTL.connect(allocator, connect_opts);
    defer client.deinit();

    try logger.info("TRANSPORT", "GTL transport initialized successfully", .{});

    // Initialize Provider Factory
    var factory = Providers.ProviderFactory.init(allocator, &client);

    // Create AI providers for metrics testing
    var openai_provider = factory.createOpenAI("demo-openai-key", "gpt-4");
    var claude_provider = factory.createClaude("demo-claude-key", "claude-3-sonnet");
    var gemini_provider = factory.createGemini("demo-gemini-key", "gemini-pro");
    var ollama_provider = factory.createOllama("http://localhost:11434", "llama2");

    try logger.info("PROVIDERS", "Initialized {d} AI providers for testing", .{4});

    // Demo different aspects of the metrics system
    try demoBasicMetrics(allocator, &logger, &metrics_collector);
    try demoRequestTracking(allocator, &logger, &metrics_collector, &openai_provider);
    try demoProviderComparison(allocator, &logger, &metrics_collector, &openai_provider, &claude_provider, &gemini_provider);
    try demoFailoverMetrics(allocator, &logger, &metrics_collector, [_]*Providers.AIProvider{ &openai_provider, &claude_provider });
    try demoMetricsReporting(allocator, &logger, &metrics_collector);
    try demoPrometheusExport(allocator, &logger, &metrics_collector);

    try logger.info("SYSTEM", "GTL metrics demo completed successfully", .{});

    std.debug.print("🎉 GTL Metrics & Logging Demo Complete!\n", .{});
    std.debug.print("Ready for production-grade observability!\n", .{});
}

fn demoBasicMetrics(allocator: std.mem.Allocator, logger: *Metrics.Logger, collector: *Metrics.MetricsCollector) !void {
    _ = allocator;

    std.debug.print("📈 Basic Metrics Collection Demo\n", .{});
    std.debug.print("=================================\n", .{});

    try logger.info("METRICS", "Starting basic metrics collection demo", .{});

    // Simulate some system metrics
    collector.system_metrics.active_connections = 15;
    collector.system_metrics.memory_usage_mb = 128.5;
    collector.system_metrics.cpu_usage_percent = 23.7;

    const system_metrics = collector.getSystemMetrics();

    std.debug.print("📊 System Status:\n", .{});
    std.debug.print("   Total Requests: {d}\n", .{system_metrics.total_requests});
    std.debug.print("   Requests/Second: {d:.2}\n", .{system_metrics.requests_per_second});
    std.debug.print("   Uptime: {d} seconds\n", .{system_metrics.uptime_seconds});
    std.debug.print("   Active Connections: {d}\n", .{system_metrics.active_connections});
    std.debug.print("   Memory Usage: {d:.1} MB\n", .{system_metrics.memory_usage_mb});

    try logger.debug("METRICS", "System metrics displayed successfully", .{});
    std.debug.print("\n");
}

fn demoRequestTracking(allocator: std.mem.Allocator, logger: *Metrics.Logger, collector: *Metrics.MetricsCollector, provider: *Providers.AIProvider) !void {
    std.debug.print("🔍 Request Tracking Demo\n", .{});
    std.debug.print("========================\n", .{});

    try logger.info("METRICS", "Starting request tracking demo with simulated requests", .{});

    // Simulate successful requests
    for (0..5) |i| {
        const request_id = try std.fmt.allocPrint(allocator, "req-{d}", .{i + 1});
        defer allocator.free(request_id);

        const start_time = std.time.milliTimestamp();
        const end_time = start_time + 150 + @as(i64, @intCast(i * 50)); // Varying latencies

        const request_metrics = Metrics.RequestMetrics{
            .request_id = request_id,
            .provider = "openai",
            .model = "gpt-4",
            .start_time = start_time,
            .end_time = end_time,
            .duration_ms = @intCast(end_time - start_time),
            .tokens_input = 25 + @as(u32, @intCast(i * 5)),
            .tokens_output = 100 + @as(u32, @intCast(i * 10)),
            .cost_usd = 0.002 + (@as(f64, @floatFromInt(i)) * 0.001),
            .success = true,
        };

        try collector.recordRequest(request_metrics);
        std.debug.print("✅ Request {d}: {d}ms, {d}→{d} tokens, ${d:.4}\n", .{
            i + 1,
            request_metrics.duration_ms,
            request_metrics.tokens_input,
            request_metrics.tokens_output,
            request_metrics.cost_usd,
        });
    }

    // Simulate a failed request
    const failed_request = Metrics.RequestMetrics{
        .request_id = "req-failed",
        .provider = "openai",
        .model = "gpt-4",
        .start_time = std.time.milliTimestamp(),
        .end_time = std.time.milliTimestamp() + 5000,
        .duration_ms = 5000,
        .tokens_input = 30,
        .tokens_output = 0,
        .cost_usd = 0.0,
        .success = false,
        .error_code = "rate_limit",
        .error_message = "Rate limit exceeded",
    };

    try collector.recordRequest(failed_request);
    std.debug.print("❌ Failed Request: Rate limit exceeded\n", .{});

    _ = provider;
    try logger.info("METRICS", "Request tracking demo completed", .{});
    std.debug.print("\n");
}

fn demoProviderComparison(allocator: std.mem.Allocator, logger: *Metrics.Logger, collector: *Metrics.MetricsCollector, openai: *Providers.AIProvider, claude: *Providers.AIProvider, gemini: *Providers.AIProvider) !void {
    _ = openai;
    _ = claude;
    _ = gemini;

    std.debug.print("⚖️  Provider Performance Comparison\n", .{});
    std.debug.print("===================================\n", .{});

    try logger.info("METRICS", "Starting provider comparison demo", .{});

    // Simulate requests to different providers
    const providers = [_]struct { name: []const u8, latency: u32, cost: f64, success_rate: f64 }{
        .{ .name = "openai", .latency = 180, .cost = 0.004, .success_rate = 0.98 },
        .{ .name = "claude", .latency = 220, .cost = 0.008, .success_rate = 0.95 },
        .{ .name = "gemini", .latency = 150, .cost = 0.001, .success_rate = 0.99 },
    };

    for (providers) |provider_info| {
        for (0..10) |i| {
            const request_id = try std.fmt.allocPrint(allocator, "{s}-req-{d}", .{ provider_info.name, i + 1 });
            defer allocator.free(request_id);

            const is_success = (i < @as(usize, @intFromFloat(provider_info.success_rate * 10)));
            const latency = provider_info.latency + @as(u32, @intCast(i * 10));

            const request_metrics = Metrics.RequestMetrics{
                .request_id = request_id,
                .provider = provider_info.name,
                .model = "auto",
                .start_time = std.time.milliTimestamp(),
                .end_time = std.time.milliTimestamp() + latency,
                .duration_ms = latency,
                .tokens_input = 50,
                .tokens_output = if (is_success) 150 else 0,
                .cost_usd = if (is_success) provider_info.cost else 0.0,
                .success = is_success,
                .error_code = if (!is_success) "timeout" else null,
                .error_message = if (!is_success) "Request timeout" else null,
            };

            try collector.recordRequest(request_metrics);
        }

        const metrics = collector.getProviderMetrics(provider_info.name).?;
        std.debug.print("📊 {s}:\n", .{provider_info.name});
        std.debug.print("   Requests: {d} (Success: {d}, Failed: {d})\n", .{
            metrics.total_requests,
            metrics.successful_requests,
            metrics.failed_requests,
        });
        std.debug.print("   Avg Latency: {d:.1}ms\n", .{metrics.average_latency_ms});
        std.debug.print("   Uptime: {d:.1}%\n", .{metrics.uptime_percentage});
        std.debug.print("   Total Cost: ${d:.4}\n", .{metrics.total_cost_usd});
    }

    try logger.info("METRICS", "Provider comparison completed", .{});
    std.debug.print("\n");
}

fn demoFailoverMetrics(allocator: std.mem.Allocator, logger: *Metrics.Logger, collector: *Metrics.MetricsCollector, providers: []*Providers.AIProvider) !void {
    std.debug.print("🔄 Failover Metrics Integration\n", .{});
    std.debug.print("===============================\n", .{});

    try logger.info("METRICS", "Starting failover metrics integration demo", .{});

    const config = Failover.LoadBalancingConfig{
        .strategy = .round_robin,
        .max_retries = 3,
        .enable_metrics = true,
    };

    var failover_manager = try Failover.FailoverManager.init(allocator, config, providers);
    defer failover_manager.deinit();

    // Simulate failover scenarios with metrics tracking
    for (0..5) |i| {
        const request_id = try std.fmt.allocPrint(allocator, "failover-req-{d}", .{i + 1});
        defer allocator.free(request_id);

        // First provider fails, second succeeds
        const failed_request = Metrics.RequestMetrics{
            .request_id = request_id,
            .provider = "openai",
            .model = "gpt-4",
            .start_time = std.time.milliTimestamp(),
            .end_time = std.time.milliTimestamp() + 5000,
            .duration_ms = 5000,
            .tokens_input = 40,
            .tokens_output = 0,
            .cost_usd = 0.0,
            .success = false,
            .error_code = "timeout",
            .error_message = "Request timeout",
        };

        try collector.recordRequest(failed_request);

        const success_request = Metrics.RequestMetrics{
            .request_id = request_id,
            .provider = "claude",
            .model = "claude-3-sonnet",
            .start_time = std.time.milliTimestamp(),
            .end_time = std.time.milliTimestamp() + 200,
            .duration_ms = 200,
            .tokens_input = 40,
            .tokens_output = 120,
            .cost_usd = 0.006,
            .success = true,
        };

        try collector.recordRequest(success_request);

        std.debug.print("🔄 Failover {d}: OpenAI failed → Claude succeeded\n", .{i + 1});
    }

    const failover_metrics = failover_manager.getMetrics();
    std.debug.print("📊 Failover Summary:\n", .{});
    std.debug.print("   Providers: {d}/{d} healthy\n", .{ failover_metrics.healthy_providers, failover_metrics.total_providers });
    std.debug.print("   Success Rate: {d:.1}%\n", .{failover_metrics.success_rate * 100});

    try logger.info("METRICS", "Failover metrics integration completed", .{});
    std.debug.print("\n");
}

fn demoMetricsReporting(allocator: std.mem.Allocator, logger: *Metrics.Logger, collector: *Metrics.MetricsCollector) !void {
    std.debug.print("📋 Metrics Reporting Demo\n", .{});
    std.debug.print("=========================\n", .{});

    try logger.info("METRICS", "Generating comprehensive metrics report", .{});

    const report = try collector.generateReport();
    defer allocator.free(report);

    std.debug.print("📄 GTL Metrics Report:\n");
    std.debug.print("{s}", .{report});

    // Export JSON metrics
    const json_metrics = try collector.exportMetricsJSON();
    defer allocator.free(json_metrics);

    std.debug.print("📊 JSON Export (first 200 chars):\n{s}...\n\n", .{json_metrics[0..@min(200, json_metrics.len)]});

    try logger.info("METRICS", "Metrics reporting completed", .{});
}

fn demoPrometheusExport(allocator: std.mem.Allocator, logger: *Metrics.Logger, collector: *Metrics.MetricsCollector) !void {
    std.debug.print("🔍 Prometheus Metrics Export\n", .{});
    std.debug.print("============================\n", .{});

    try logger.info("METRICS", "Generating Prometheus-compatible metrics", .{});

    var prometheus_exporter = Metrics.PrometheusExporter.init(allocator, collector);
    const prometheus_metrics = try prometheus_exporter.exportMetrics();
    defer allocator.free(prometheus_metrics);

    std.debug.print("📊 Prometheus Metrics (first 500 chars):\n{s}...\n\n", .{prometheus_metrics[0..@min(500, prometheus_metrics.len)]});

    try logger.info("METRICS", "Prometheus export completed", .{});
}

test "metrics system integration" {
    const allocator = std.testing.allocator;

    // Test logger
    var logger = try Metrics.Logger.init(allocator, .debug, false, null);
    defer logger.deinit();

    try logger.info("TEST", "Test log message", .{});

    // Test metrics collector
    var collector = Metrics.MetricsCollector.init(allocator, &logger, false);
    defer collector.deinit();

    const test_request = Metrics.RequestMetrics{
        .request_id = "test-req",
        .provider = "test-provider",
        .model = "test-model",
        .start_time = 1000,
        .end_time = 1200,
        .duration_ms = 200,
        .tokens_input = 50,
        .tokens_output = 100,
        .cost_usd = 0.005,
        .success = true,
    };

    try collector.recordRequest(test_request);

    const metrics = collector.getProviderMetrics("test-provider").?;
    try std.testing.expect(metrics.total_requests == 1);
    try std.testing.expect(metrics.successful_requests == 1);
    try std.testing.expect(metrics.average_latency_ms == 200.0);

    // Test Prometheus exporter
    var prometheus = Metrics.PrometheusExporter.init(allocator, &collector);
    const output = try prometheus.exportMetrics();
    defer allocator.free(output);

    try std.testing.expect(output.len > 0);
}