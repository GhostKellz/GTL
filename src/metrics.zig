const std = @import("std");
const Events = @import("events.zig");
const Providers = @import("providers.zig");

// GTL Comprehensive Logging and Metrics System
// Enterprise-grade observability for AI provider operations

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
    fatal,
};

pub const MetricType = enum {
    counter,
    gauge,
    histogram,
    timer,
};

pub const RequestMetrics = struct {
    request_id: []const u8,
    provider: []const u8,
    model: []const u8,
    start_time: i64,
    end_time: i64,
    duration_ms: u32,
    tokens_input: u32,
    tokens_output: u32,
    cost_usd: f64,
    success: bool,
    error_code: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
};

pub const ProviderMetrics = struct {
    provider_name: []const u8,
    total_requests: u32 = 0,
    successful_requests: u32 = 0,
    failed_requests: u32 = 0,
    total_tokens_input: u32 = 0,
    total_tokens_output: u32 = 0,
    total_cost_usd: f64 = 0.0,
    average_latency_ms: f64 = 0.0,
    last_request_time: i64 = 0,
    uptime_percentage: f64 = 100.0,
};

pub const SystemMetrics = struct {
    total_requests: u32 = 0,
    requests_per_second: f64 = 0.0,
    active_connections: u32 = 0,
    memory_usage_mb: f64 = 0.0,
    cpu_usage_percent: f64 = 0.0,
    start_time: i64,
    uptime_seconds: i64 = 0,
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    log_level: LogLevel,
    enable_console: bool,
    enable_file: bool,
    log_file_path: ?[]const u8,
    log_file: ?std.fs.File = null,
    buffer: std.array_list.AlignedManaged(u8, null),

    pub fn init(allocator: std.mem.Allocator, level: LogLevel, enable_console: bool, log_file_path: ?[]const u8) !Logger {
        var logger = Logger{
            .allocator = allocator,
            .log_level = level,
            .enable_console = enable_console,
            .enable_file = log_file_path != null,
            .log_file_path = log_file_path,
            .buffer = std.array_list.AlignedManaged(u8, null).init(allocator),
        };

        if (log_file_path) |path| {
            logger.log_file = std.fs.cwd().createFile(path, .{}) catch |file_err| {
                std.debug.print("Warning: Could not create log file {s}: {}\n", .{ path, file_err });
                logger.enable_file = false;
                return logger;
            };
        }

        return logger;
    }

    pub fn deinit(self: *Logger) void {
        if (self.log_file) |file| {
            file.close();
        }
        self.buffer.deinit();
    }

    pub fn log(self: *Logger, level: LogLevel, component: []const u8, message: []const u8, args: anytype) !void {
        if (@intFromEnum(level) < @intFromEnum(self.log_level)) {
            return;
        }

        const timestamp = std.time.timestamp();
        const formatted_time = try self.formatTimestamp(timestamp);

        self.buffer.clearRetainingCapacity();

        try self.buffer.appendSlice("[");
        try self.buffer.appendSlice(formatted_time);
        try self.buffer.appendSlice("] [");
        try self.buffer.appendSlice(@tagName(level));
        try self.buffer.appendSlice("] [");
        try self.buffer.appendSlice(component);
        try self.buffer.appendSlice("] ");

        const formatted_message = try std.fmt.allocPrint(self.allocator, message, args);
        defer self.allocator.free(formatted_message);
        try self.buffer.appendSlice(formatted_message);
        try self.buffer.appendSlice("\n");

        const log_line = self.buffer.items;

        if (self.enable_console) {
            std.debug.print("{s}", .{log_line});
        }

        if (self.enable_file and self.log_file != null) {
            _ = self.log_file.?.write(log_line) catch |write_err| {
                std.debug.print("Warning: Could not write to log file: {}\n", .{write_err});
            };
        }
    }

    fn formatTimestamp(self: *Logger, timestamp: i64) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{d}", .{timestamp});
    }

    pub fn debug(self: *Logger, component: []const u8, message: []const u8, args: anytype) !void {
        try self.log(.debug, component, message, args);
    }

    pub fn info(self: *Logger, component: []const u8, message: []const u8, args: anytype) !void {
        try self.log(.info, component, message, args);
    }

    pub fn warn(self: *Logger, component: []const u8, message: []const u8, args: anytype) !void {
        try self.log(.warn, component, message, args);
    }

    pub fn err(self: *Logger, component: []const u8, message: []const u8, args: anytype) !void {
        try self.log(.err, component, message, args);
    }

    pub fn fatal(self: *Logger, component: []const u8, message: []const u8, args: anytype) !void {
        try self.log(.fatal, component, message, args);
    }
};

pub const MetricsCollector = struct {
    allocator: std.mem.Allocator,
    logger: *Logger,
    system_metrics: SystemMetrics,
    provider_metrics: std.HashMap([]const u8, ProviderMetrics, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    request_history: std.array_list.AlignedManaged(RequestMetrics, null),
    enable_detailed_logging: bool,

    pub fn init(allocator: std.mem.Allocator, logger: *Logger, enable_detailed_logging: bool) MetricsCollector {
        return MetricsCollector{
            .allocator = allocator,
            .logger = logger,
            .system_metrics = SystemMetrics{
                .start_time = std.time.timestamp(),
            },
            .provider_metrics = std.HashMap([]const u8, ProviderMetrics, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .request_history = std.array_list.AlignedManaged(RequestMetrics, null).init(allocator),
            .enable_detailed_logging = enable_detailed_logging,
        };
    }

    pub fn deinit(self: *MetricsCollector) void {
        self.provider_metrics.deinit();
        self.request_history.deinit();
    }

    pub fn recordRequest(self: *MetricsCollector, request_metrics: RequestMetrics) !void {
        // Update system metrics
        self.system_metrics.total_requests += 1;
        self.system_metrics.uptime_seconds = std.time.timestamp() - self.system_metrics.start_time;

        // Update provider metrics
        const provider_entry = try self.provider_metrics.getOrPut(request_metrics.provider);
        if (!provider_entry.found_existing) {
            provider_entry.value_ptr.* = ProviderMetrics{
                .provider_name = try self.allocator.dupe(u8, request_metrics.provider),
            };
        }

        var provider_metrics = provider_entry.value_ptr;
        provider_metrics.total_requests += 1;
        provider_metrics.last_request_time = request_metrics.end_time;
        provider_metrics.total_tokens_input += request_metrics.tokens_input;
        provider_metrics.total_tokens_output += request_metrics.tokens_output;
        provider_metrics.total_cost_usd += request_metrics.cost_usd;

        if (request_metrics.success) {
            provider_metrics.successful_requests += 1;
        } else {
            provider_metrics.failed_requests += 1;
        }

        // Update average latency
        const total_successful = provider_metrics.successful_requests;
        if (total_successful > 0) {
            provider_metrics.average_latency_ms = (provider_metrics.average_latency_ms * @as(f64, @floatFromInt(total_successful - 1)) + @as(f64, @floatFromInt(request_metrics.duration_ms))) / @as(f64, @floatFromInt(total_successful));
        }

        // Update uptime percentage
        if (provider_metrics.total_requests > 0) {
            provider_metrics.uptime_percentage = (@as(f64, @floatFromInt(provider_metrics.successful_requests)) / @as(f64, @floatFromInt(provider_metrics.total_requests))) * 100.0;
        }

        // Store request history if detailed logging is enabled
        if (self.enable_detailed_logging) {
            try self.request_history.append(request_metrics);
        }

        // Log the request
        if (request_metrics.success) {
            try self.logger.info("METRICS", "Request completed - Provider: {s}, Model: {s}, Duration: {d}ms, Tokens: {d}→{d}, Cost: ${d:.4}", .{
                request_metrics.provider,
                request_metrics.model,
                request_metrics.duration_ms,
                request_metrics.tokens_input,
                request_metrics.tokens_output,
                request_metrics.cost_usd,
            });
        } else {
            try self.logger.err("METRICS", "Request failed - Provider: {s}, Model: {s}, Error: {s}", .{
                request_metrics.provider,
                request_metrics.model,
                request_metrics.error_message orelse "Unknown error",
            });
        }
    }

    pub fn getSystemMetrics(self: *MetricsCollector) SystemMetrics {
        self.system_metrics.uptime_seconds = std.time.timestamp() - self.system_metrics.start_time;

        // Calculate requests per second
        if (self.system_metrics.uptime_seconds > 0) {
            self.system_metrics.requests_per_second = @as(f64, @floatFromInt(self.system_metrics.total_requests)) / @as(f64, @floatFromInt(self.system_metrics.uptime_seconds));
        }

        return self.system_metrics;
    }

    pub fn getProviderMetrics(self: *MetricsCollector, provider_name: []const u8) ?ProviderMetrics {
        return self.provider_metrics.get(provider_name);
    }

    pub fn getAllProviderMetrics(self: *MetricsCollector) std.HashMap([]const u8, ProviderMetrics, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).Iterator {
        return self.provider_metrics.iterator();
    }

    pub fn generateReport(self: *MetricsCollector) ![]u8 {
        var report = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer report.deinit();

        const system_metrics = self.getSystemMetrics();

        try report.appendSlice("GTL Metrics Report\n");
        try report.appendSlice("==================\n\n");

        // System metrics
        try report.appendSlice("System Metrics:\n");
        const system_section = try std.fmt.allocPrint(self.allocator,
            "  Total Requests: {d}\n" ++
            "  Requests/Second: {d:.2}\n" ++
            "  Uptime: {d} seconds\n" ++
            "  Active Connections: {d}\n\n",
            .{
                system_metrics.total_requests,
                system_metrics.requests_per_second,
                system_metrics.uptime_seconds,
                system_metrics.active_connections,
            }
        );
        defer self.allocator.free(system_section);
        try report.appendSlice(system_section);

        // Provider metrics
        try report.appendSlice("Provider Metrics:\n");
        var provider_iter = self.getAllProviderMetrics();
        while (provider_iter.next()) |entry| {
            const provider_section = try std.fmt.allocPrint(self.allocator,
                "  {s}:\n" ++
                "    Requests: {d} (Success: {d}, Failed: {d})\n" ++
                "    Uptime: {d:.1}%\n" ++
                "    Avg Latency: {d:.1}ms\n" ++
                "    Tokens: {d} in, {d} out\n" ++
                "    Total Cost: ${d:.4}\n\n",
                .{
                    entry.key_ptr.*,
                    entry.value_ptr.total_requests,
                    entry.value_ptr.successful_requests,
                    entry.value_ptr.failed_requests,
                    entry.value_ptr.uptime_percentage,
                    entry.value_ptr.average_latency_ms,
                    entry.value_ptr.total_tokens_input,
                    entry.value_ptr.total_tokens_output,
                    entry.value_ptr.total_cost_usd,
                }
            );
            defer self.allocator.free(provider_section);
            try report.appendSlice(provider_section);
        }

        return try report.toOwnedSlice();
    }

    pub fn exportMetricsJSON(self: *MetricsCollector) ![]u8 {
        var json = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer json.deinit();

        const system_metrics = self.getSystemMetrics();

        try json.appendSlice("{\"system\":{");
        const system_json = try std.fmt.allocPrint(self.allocator,
            "\"total_requests\":{d}," ++
            "\"requests_per_second\":{d:.2}," ++
            "\"uptime_seconds\":{d}," ++
            "\"active_connections\":{d}",
            .{
                system_metrics.total_requests,
                system_metrics.requests_per_second,
                system_metrics.uptime_seconds,
                system_metrics.active_connections,
            }
        );
        defer self.allocator.free(system_json);
        try json.appendSlice(system_json);

        try json.appendSlice("},\"providers\":{");

        var provider_iter = self.getAllProviderMetrics();
        var first = true;
        while (provider_iter.next()) |entry| {
            if (!first) try json.appendSlice(",");
            first = false;

            try json.appendSlice("\"");
            try json.appendSlice(entry.key_ptr.*);
            try json.appendSlice("\":{");

            const provider_json = try std.fmt.allocPrint(self.allocator,
                "\"total_requests\":{d}," ++
                "\"successful_requests\":{d}," ++
                "\"failed_requests\":{d}," ++
                "\"uptime_percentage\":{d:.1}," ++
                "\"average_latency_ms\":{d:.1}," ++
                "\"total_tokens_input\":{d}," ++
                "\"total_tokens_output\":{d}," ++
                "\"total_cost_usd\":{d:.4}",
                .{
                    entry.value_ptr.total_requests,
                    entry.value_ptr.successful_requests,
                    entry.value_ptr.failed_requests,
                    entry.value_ptr.uptime_percentage,
                    entry.value_ptr.average_latency_ms,
                    entry.value_ptr.total_tokens_input,
                    entry.value_ptr.total_tokens_output,
                    entry.value_ptr.total_cost_usd,
                }
            );
            defer self.allocator.free(provider_json);
            try json.appendSlice(provider_json);
            try json.appendSlice("}");
        }

        try json.appendSlice("}}");
        return try json.toOwnedSlice();
    }
};

// Prometheus-style metrics exporter
pub const PrometheusExporter = struct {
    allocator: std.mem.Allocator,
    metrics_collector: *MetricsCollector,

    pub fn init(allocator: std.mem.Allocator, collector: *MetricsCollector) PrometheusExporter {
        return PrometheusExporter{
            .allocator = allocator,
            .metrics_collector = collector,
        };
    }

    pub fn exportMetrics(self: *PrometheusExporter) ![]u8 {
        var output = std.array_list.AlignedManaged(u8, null).init(self.allocator);
        defer output.deinit();

        const system_metrics = self.metrics_collector.getSystemMetrics();

        // System metrics
        try output.appendSlice("# HELP gtl_total_requests Total number of GTL requests\n");
        try output.appendSlice("# TYPE gtl_total_requests counter\n");
        const total_requests = try std.fmt.allocPrint(self.allocator, "gtl_total_requests {d}\n", .{system_metrics.total_requests});
        defer self.allocator.free(total_requests);
        try output.appendSlice(total_requests);

        try output.appendSlice("\n# HELP gtl_requests_per_second Current requests per second\n");
        try output.appendSlice("# TYPE gtl_requests_per_second gauge\n");
        const rps = try std.fmt.allocPrint(self.allocator, "gtl_requests_per_second {d:.2}\n", .{system_metrics.requests_per_second});
        defer self.allocator.free(rps);
        try output.appendSlice(rps);

        // Provider metrics
        try output.appendSlice("\n# HELP gtl_provider_requests Total requests per provider\n");
        try output.appendSlice("# TYPE gtl_provider_requests counter\n");

        var provider_iter = self.metrics_collector.getAllProviderMetrics();
        while (provider_iter.next()) |entry| {
            const provider_requests = try std.fmt.allocPrint(self.allocator, "gtl_provider_requests{{provider=\"{s}\"}} {d}\n", .{ entry.key_ptr.*, entry.value_ptr.total_requests });
            defer self.allocator.free(provider_requests);
            try output.appendSlice(provider_requests);
        }

        try output.appendSlice("\n# HELP gtl_provider_latency_ms Average latency per provider in milliseconds\n");
        try output.appendSlice("# TYPE gtl_provider_latency_ms gauge\n");

        provider_iter = self.metrics_collector.getAllProviderMetrics();
        while (provider_iter.next()) |entry| {
            const provider_latency = try std.fmt.allocPrint(self.allocator, "gtl_provider_latency_ms{{provider=\"{s}\"}} {d:.1}\n", .{ entry.key_ptr.*, entry.value_ptr.average_latency_ms });
            defer self.allocator.free(provider_latency);
            try output.appendSlice(provider_latency);
        }

        return try output.toOwnedSlice();
    }
};