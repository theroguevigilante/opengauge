const std = @import("std");

pub const RunResult = struct {
    ttft_ms: u64,
    total_ms: u64,
    tokens_generated: u32,
};

pub const Stats = struct {
    n: u32,
    mean_ttft_ms: f64,
    p50_ttft_ms: f64,
    mean_ms: f64,
    p50_ms: f64,
    p90_ms: f64,
    mean_tok_s: f64,

    /// Computes stats from a slice of results. Sorts the slice in place by total_ms.
    /// Caller must ensure results.len > 0.
    pub fn compute(results: []RunResult) Stats {
        var total_ttft_ms: u64 = 0;
        var total_ms: u64 = 0;
        var total_tokens: u64 = 0;
        for (results) |r| {
            total_ttft_ms += r.ttft_ms;
            total_ms += r.total_ms;
            total_tokens += r.tokens_generated;
        }

        const n = results.len;
        const nf = @as(f64, @floatFromInt(n));

        var ttft_buf: [256]u64 = undefined;
        var p50_ttft: f64 = @as(f64, @floatFromInt(total_ttft_ms)) / nf;
        if (n <= ttft_buf.len) {
            const s = ttft_buf[0..n];
            for (results, 0..) |r, i| s[i] = r.ttft_ms;
            std.mem.sort(u64, s, {}, std.sort.asc(u64));
            p50_ttft = @floatFromInt(s[n / 2]);
        }

        std.mem.sort(RunResult, results, {}, struct {
            fn lt(_: void, a: RunResult, b: RunResult) bool {
                return a.total_ms < b.total_ms;
            }
        }.lt);

        return .{
            .n = @intCast(n),
            .mean_ttft_ms = @as(f64, @floatFromInt(total_ttft_ms)) / nf,
            .p50_ttft_ms = p50_ttft,
            .mean_ms = @as(f64, @floatFromInt(total_ms)) / nf,
            .p50_ms = @floatFromInt(results[n / 2].total_ms),
            .p90_ms = @floatFromInt(results[(n * 9) / 10].total_ms),
            .mean_tok_s = @as(f64, @floatFromInt(total_tokens)) /
                (@as(f64, @floatFromInt(total_ms)) / 1000.0),
        };
    }
};

test "Stats.compute single run with TTFT" {
    var results = [_]RunResult{.{ .ttft_ms = 45, .total_ms = 200, .tokens_generated = 20 }};
    const s = Stats.compute(&results);
    try std.testing.expectEqual(@as(u32, 1), s.n);
    try std.testing.expectApproxEqAbs(@as(f64, 45.0), s.mean_ttft_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 45.0), s.p50_ttft_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), s.mean_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), s.mean_tok_s, 0.01);
}

test "Stats.compute percentiles and TTFT" {
    var results = [_]RunResult{
        .{ .ttft_ms = 80, .total_ms = 500, .tokens_generated = 50 },
        .{ .ttft_ms = 20, .total_ms = 100, .tokens_generated = 10 },
        .{ .ttft_ms = 50, .total_ms = 300, .tokens_generated = 30 },
        .{ .ttft_ms = 40, .total_ms = 200, .tokens_generated = 20 },
        .{ .ttft_ms = 60, .total_ms = 400, .tokens_generated = 40 },
    };
    const s = Stats.compute(&results);
    try std.testing.expectEqual(@as(u32, 5), s.n);
    // ttft sorted: [20, 40, 50, 60, 80], mean = 250 / 5 = 50
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), s.mean_ttft_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), s.p50_ttft_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), s.mean_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), s.p50_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 500.0), s.p90_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), s.mean_tok_s, 0.01);
}
