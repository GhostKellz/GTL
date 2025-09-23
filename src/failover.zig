const std = @import("std");
const Providers = @import("providers.zig");
const Events = @import("events.zig");

// GTL Provider Failover and Load Balancing System
// Intelligent provider selection and automatic failover for reliability

pub const FailoverStrategy = enum {
    round_robin,
    priority_order,
    least_latency,
    cost_optimized,
    random,
};

pub const LoadBalancingConfig = struct {
    strategy: FailoverStrategy = .priority_order,
    max_retries: u8 = 3,
    retry_delay_ms: u32 = 1000,
    health_check_interval_ms: u32 = 30000,
    circuit_breaker_threshold: u8 = 5,
    enable_metrics: bool = true,
};

pub const ProviderHealth = struct {
    provider: *Providers.AIProvider,
    is_healthy: bool = true,
    last_response_time_ms: u32 = 0,
    error_count: u8 = 0,
    last_health_check: i64 = 0,
    total_requests: u32 = 0,
    successful_requests: u32 = 0,
};

pub const FailoverManager = struct {
    allocator: std.mem.Allocator,
    config: LoadBalancingConfig,
    providers: []ProviderHealth,
    current_provider_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: LoadBalancingConfig, providers: []*Providers.AIProvider) !FailoverManager {
        var provider_health = try allocator.alloc(ProviderHealth, providers.len);

        for (providers, 0..) |provider, i| {
            provider_health[i] = ProviderHealth{
                .provider = provider,
            };
        }

        return FailoverManager{
            .allocator = allocator,
            .config = config,
            .providers = provider_health,
        };
    }

    pub fn deinit(self: *FailoverManager) void {
        self.allocator.free(self.providers);
    }

    pub fn complete(self: *FailoverManager, request: Providers.CompletionRequest) ![]u8 {
        var attempts: u8 = 0;
        var last_error: ?anyerror = null;

        while (attempts < self.config.max_retries) {
            const provider_index = try self.selectProvider();
            const provider_health = &self.providers[provider_index];

            if (!provider_health.is_healthy) {
                attempts += 1;
                continue;
            }

            const start_time = std.time.milliTimestamp();

            const response = provider_health.provider.complete(request) catch |err| {
                last_error = err;
                self.recordFailure(provider_index);
                attempts += 1;

                // Wait before retry
                if (attempts < self.config.max_retries) {
                    std.time.sleep(self.config.retry_delay_ms * std.time.ns_per_ms);
                }
                continue;
            };

            const end_time = std.time.milliTimestamp();
            self.recordSuccess(provider_index, @intCast(end_time - start_time));

            return response;
        }

        return last_error orelse error.AllProvidersFailed;
    }

    pub fn stream(self: *FailoverManager, request: Providers.CompletionRequest, handler: Events.EventHandler) !void {
        var attempts: u8 = 0;
        var last_error: ?anyerror = null;

        while (attempts < self.config.max_retries) {
            const provider_index = try self.selectProvider();
            const provider_health = &self.providers[provider_index];

            if (!provider_health.is_healthy) {
                attempts += 1;
                continue;
            }

            const start_time = std.time.milliTimestamp();

            provider_health.provider.stream(request, handler) catch |err| {
                last_error = err;
                self.recordFailure(provider_index);
                attempts += 1;

                // Wait before retry
                if (attempts < self.config.max_retries) {
                    std.time.sleep(self.config.retry_delay_ms * std.time.ns_per_ms);
                }
                continue;
            };

            const end_time = std.time.milliTimestamp();
            self.recordSuccess(provider_index, @intCast(end_time - start_time));

            return;
        }

        return last_error orelse error.AllProvidersFailed;
    }

    fn selectProvider(self: *FailoverManager) !usize {
        switch (self.config.strategy) {
            .round_robin => return self.selectRoundRobin(),
            .priority_order => return self.selectPriorityOrder(),
            .least_latency => return self.selectLeastLatency(),
            .cost_optimized => return self.selectCostOptimized(),
            .random => return self.selectRandom(),
        }
    }

    fn selectRoundRobin(self: *FailoverManager) usize {
        const start_index = self.current_provider_index;

        for (0..self.providers.len) |offset| {
            const index = (start_index + offset) % self.providers.len;
            if (self.providers[index].is_healthy) {
                self.current_provider_index = (index + 1) % self.providers.len;
                return index;
            }
        }

        // Fallback to first provider if none are healthy
        return 0;
    }

    fn selectPriorityOrder(self: *FailoverManager) usize {
        for (self.providers, 0..) |provider_health, i| {
            if (provider_health.is_healthy) {
                return i;
            }
        }

        // Fallback to first provider if none are healthy
        return 0;
    }

    fn selectLeastLatency(self: *FailoverManager) usize {
        var best_index: usize = 0;
        var best_latency: u32 = std.math.maxInt(u32);

        for (self.providers, 0..) |provider_health, i| {
            if (provider_health.is_healthy and provider_health.last_response_time_ms < best_latency) {
                best_latency = provider_health.last_response_time_ms;
                best_index = i;
            }
        }

        return best_index;
    }

    fn selectCostOptimized(self: *FailoverManager) usize {
        var best_index: usize = 0;
        var best_cost: f64 = std.math.floatMax(f64);

        for (self.providers, 0..) |provider_health, i| {
            if (provider_health.is_healthy) {
                const config = provider_health.provider.config;
                const estimated_cost = config.capabilities.cost_per_1k_input + config.capabilities.cost_per_1k_output;

                if (estimated_cost < best_cost) {
                    best_cost = estimated_cost;
                    best_index = i;
                }
            }
        }

        return best_index;
    }

    fn selectRandom(self: *FailoverManager) usize {
        var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const random = prng.random();

        // Collect healthy providers
        var healthy_indices = std.array_list.AlignedManaged(usize, null).init(self.allocator);
        defer healthy_indices.deinit();

        for (self.providers, 0..) |provider_health, i| {
            if (provider_health.is_healthy) {
                healthy_indices.append(i) catch return 0;
            }
        }

        if (healthy_indices.items.len == 0) return 0;

        const random_index = random.uintLessThan(usize, healthy_indices.items.len);
        return healthy_indices.items[random_index];
    }

    fn recordSuccess(self: *FailoverManager, provider_index: usize, response_time_ms: u32) void {
        var provider_health = &self.providers[provider_index];

        provider_health.last_response_time_ms = response_time_ms;
        provider_health.error_count = 0;
        provider_health.total_requests += 1;
        provider_health.successful_requests += 1;
        provider_health.is_healthy = true;
    }

    fn recordFailure(self: *FailoverManager, provider_index: usize) void {
        var provider_health = &self.providers[provider_index];

        provider_health.error_count += 1;
        provider_health.total_requests += 1;

        // Circuit breaker logic
        if (provider_health.error_count >= self.config.circuit_breaker_threshold) {
            provider_health.is_healthy = false;
        }
    }

    pub fn healthCheck(self: *FailoverManager) !void {
        const current_time = std.time.milliTimestamp();

        for (self.providers, 0..) |*provider_health, i| {
            if (current_time - provider_health.last_health_check < self.config.health_check_interval_ms) {
                continue;
            }

            // Simple health check - try a minimal request
            const health_request = Providers.CompletionRequest{
                .messages = &[_]Providers.Message{
                    .{ .role = .user, .content = "ping" },
                },
                .model = provider_health.provider.config.model,
                .max_tokens = 1,
                .stream = false,
            };

            const start_time = std.time.milliTimestamp();

            if (provider_health.provider.complete(health_request)) |response| {
                defer self.allocator.free(response);
                const end_time = std.time.milliTimestamp();
                self.recordSuccess(i, @intCast(end_time - start_time));
            } else |_| {
                self.recordFailure(i);
            }

            provider_health.last_health_check = current_time;
        }
    }

    pub fn getMetrics(self: *FailoverManager) FailoverMetrics {
        var metrics = FailoverMetrics{
            .total_providers = self.providers.len,
            .healthy_providers = 0,
            .total_requests = 0,
            .successful_requests = 0,
            .average_latency_ms = 0,
        };

        var total_latency: u64 = 0;
        var latency_count: u32 = 0;

        for (self.providers) |provider_health| {
            if (provider_health.is_healthy) {
                metrics.healthy_providers += 1;
            }

            metrics.total_requests += provider_health.total_requests;
            metrics.successful_requests += provider_health.successful_requests;

            if (provider_health.last_response_time_ms > 0) {
                total_latency += provider_health.last_response_time_ms;
                latency_count += 1;
            }
        }

        if (latency_count > 0) {
            metrics.average_latency_ms = @intCast(total_latency / latency_count);
        }

        if (metrics.total_requests > 0) {
            metrics.success_rate = @as(f64, @floatFromInt(metrics.successful_requests)) / @as(f64, @floatFromInt(metrics.total_requests));
        }

        return metrics;
    }
};

pub const FailoverMetrics = struct {
    total_providers: usize,
    healthy_providers: usize,
    total_requests: u32,
    successful_requests: u32,
    success_rate: f64 = 0.0,
    average_latency_ms: u32,
};

// Circuit Breaker Implementation
pub const CircuitBreaker = struct {
    failure_threshold: u8,
    recovery_timeout_ms: u32,
    failure_count: u8 = 0,
    last_failure_time: i64 = 0,
    state: State = .closed,

    const State = enum {
        closed,    // Normal operation
        open,      // Failing, reject requests
        half_open, // Testing if recovered
    };

    pub fn init(failure_threshold: u8, recovery_timeout_ms: u32) CircuitBreaker {
        return CircuitBreaker{
            .failure_threshold = failure_threshold,
            .recovery_timeout_ms = recovery_timeout_ms,
        };
    }

    pub fn canExecute(self: *CircuitBreaker) bool {
        const current_time = std.time.milliTimestamp();

        switch (self.state) {
            .closed => return true,
            .open => {
                if (current_time - self.last_failure_time > self.recovery_timeout_ms) {
                    self.state = .half_open;
                    return true;
                }
                return false;
            },
            .half_open => return true,
        }
    }

    pub fn recordSuccess(self: *CircuitBreaker) void {
        self.failure_count = 0;
        self.state = .closed;
    }

    pub fn recordFailure(self: *CircuitBreaker) void {
        self.failure_count += 1;
        self.last_failure_time = std.time.milliTimestamp();

        if (self.failure_count >= self.failure_threshold) {
            self.state = .open;
        }
    }
};