const std = @import("std");

pub const RunResult = struct {
    total_ms: u64,
    tokens_generated: u32,
};

pub const Stats = struct {
    n: u32,
    mean_ms: f64,
    p50_ms: f64,
    p90_ms: f64,
    mean_tok_s: f64,

    /// Computes stats from a slice of results. Sorts the slice in place.
    /// Caller must ensure results.len > 0.
    pub fn compute(results: []RunResult) Stats {
        std.mem.sort(RunResult, results, {}, struct {
            fn lt(_: void, a: RunResult, b: RunResult) bool {
                return a.total_ms < b.total_ms;
            }
        }.lt);

        var total_ms: u64 = 0;
        var total_tokens: u64 = 0;
        for (results) |r| {
            total_ms += r.total_ms;
            total_tokens += r.tokens_generated;
        }

        const n = results.len;
        const nf = @as(f64, @floatFromInt(n));

        return .{
            .n = @intCast(n),
            .mean_ms = @as(f64, @floatFromInt(total_ms)) / nf,
            .p50_ms = @floatFromInt(results[n / 2].total_ms),
            .p90_ms = @floatFromInt(results[(n * 9) / 10].total_ms),
            .mean_tok_s = @as(f64, @floatFromInt(total_tokens)) /
                (@as(f64, @floatFromInt(total_ms)) / 1000.0),
        };
    }
};

test "Stats.compute single run" {
    var results = [_]RunResult{.{ .total_ms = 200, .tokens_generated = 20 }};
    const s = Stats.compute(&results);
    try std.testing.expectEqual(@as(u32, 1), s.n);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), s.mean_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), s.mean_tok_s, 0.01);
}

test "Stats.compute percentiles" {
    var results = [_]RunResult{
        .{ .total_ms = 500, .tokens_generated = 50 },
        .{ .total_ms = 100, .tokens_generated = 10 },
        .{ .total_ms = 300, .tokens_generated = 30 },
        .{ .total_ms = 200, .tokens_generated = 20 },
        .{ .total_ms = 400, .tokens_generated = 40 },
    };
    const s = Stats.compute(&results);
    try std.testing.expectEqual(@as(u32, 5), s.n);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), s.mean_ms, 0.01);
    // sorted: [100, 200, 300, 400, 500] — n/2 = index 2 = 300
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), s.p50_ms, 0.01);
    // (5 * 9) / 10 = index 4 = 500
    try std.testing.expectApproxEqAbs(@as(f64, 500.0), s.p90_ms, 0.01);
    // total_tokens=150, total_ms=1500 → 150 / 1.5 = 100 tok/s
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), s.mean_tok_s, 0.01);
}
