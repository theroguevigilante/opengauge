const std = @import("std");
const ModelProfile = @import("../profile.zig").ModelProfile;

pub const Priority = enum {
    auto,
    speed,
    quality,

    pub fn fromString(str: []const u8) Priority {
        if (std.ascii.eqlIgnoreCase(str, "speed")) return .speed;
        if (std.ascii.eqlIgnoreCase(str, "quality")) return .quality;
        return .auto;
    }
};

pub const RouteCriteria = struct {
    prompt_len: usize = 0,
    max_tokens: ?u32 = null,
    priority: Priority = .auto,
};

/// Selects the optimal ModelProfile from available benchmarked profiles based on RouteCriteria.
/// Returns null if profiles is empty.
pub fn selectProfile(profiles: []const ModelProfile, criteria: RouteCriteria) ?ModelProfile {
    if (profiles.len == 0) return null;

    const resolved_priority: Priority = switch (criteria.priority) {
        .auto => blk: {
            // Heuristic: short prompts (< 300 chars) with small or unspecified max_tokens (<= 128)
            // represent quick edits or autocompletions demanding low TTFT.
            // Longer prompts or large generation budgets demand reasoning/quality.
            const is_short_prompt = criteria.prompt_len < 300;
            const is_small_gen = if (criteria.max_tokens) |mt| mt <= 128 else true;
            if (is_short_prompt and is_small_gen) {
                break :blk .speed;
            }
            break :blk .quality;
        },
        .speed => .speed,
        .quality => .quality,
    };

    switch (resolved_priority) {
        .speed => {
            // Pick model with lowest TTFT (favoring models with quality >= 50 if scored)
            var best: ?ModelProfile = null;
            for (profiles) |p| {
                if (best == null) {
                    best = p;
                    continue;
                }
                const b = best.?;

                const p_quality_ok = if (p.quality) |q| q >= 50.0 else true;
                const b_quality_ok = if (b.quality) |q| q >= 50.0 else true;

                if (p_quality_ok and !b_quality_ok) {
                    best = p;
                } else if (p_quality_ok == b_quality_ok) {
                    if (p.ttft_ms < b.ttft_ms) {
                        best = p;
                    }
                }
            }
            return best;
        },
        .quality => {
            // Pick model with highest quality score. Tiebreaker on throughput (tok_s).
            var best: ?ModelProfile = null;
            for (profiles) |p| {
                if (best == null) {
                    best = p;
                    continue;
                }
                const b = best.?;

                const p_q = p.quality orelse 0.0;
                const b_q = b.quality orelse 0.0;

                if (p_q > b_q) {
                    best = p;
                } else if (p_q == b_q) {
                    if (p.tok_s > b.tok_s) {
                        best = p;
                    }
                }
            }
            return best;
        },
        .auto => unreachable,
    }
}

test "Priority.fromString parsing" {
    try std.testing.expectEqual(Priority.speed, Priority.fromString("speed"));
    try std.testing.expectEqual(Priority.speed, Priority.fromString("SPEED"));
    try std.testing.expectEqual(Priority.quality, Priority.fromString("quality"));
    try std.testing.expectEqual(Priority.auto, Priority.fromString("auto"));
    try std.testing.expectEqual(Priority.auto, Priority.fromString("unknown"));
}

test "selectProfile on empty list returns null" {
    const result = selectProfile(&.{}, .{});
    try std.testing.expect(result == null);
}

test "selectProfile routes by speed" {
    const fast_model = ModelProfile{
        .model = "mobilellm:125m",
        .backend = "ollama",
        .base_url = "http://localhost:11434",
        .runs = 3,
        .ttft_ms = 18.0,
        .mean_ms = 200.0,
        .p50_ms = 190.0,
        .p90_ms = 220.0,
        .tok_s = 85.0,
        .quality = 65.0,
    };
    const slow_model = ModelProfile{
        .model = "deepseek:7b",
        .backend = "ollama",
        .base_url = "http://localhost:11434",
        .runs = 3,
        .ttft_ms = 95.0,
        .mean_ms = 1200.0,
        .p50_ms = 1100.0,
        .p90_ms = 1400.0,
        .tok_s = 32.0,
        .quality = 92.0,
    };

    const profiles = [_]ModelProfile{ slow_model, fast_model };
    const routed = selectProfile(&profiles, .{ .priority = .speed });
    try std.testing.expect(routed != null);
    try std.testing.expectEqualStrings("mobilellm:125m", routed.?.model);
}

test "selectProfile routes by quality" {
    const fast_model = ModelProfile{
        .model = "mobilellm:125m",
        .backend = "ollama",
        .base_url = "http://localhost:11434",
        .runs = 3,
        .ttft_ms = 18.0,
        .mean_ms = 200.0,
        .p50_ms = 190.0,
        .p90_ms = 220.0,
        .tok_s = 85.0,
        .quality = 65.0,
    };
    const quality_model = ModelProfile{
        .model = "deepseek:7b",
        .backend = "ollama",
        .base_url = "http://localhost:11434",
        .runs = 3,
        .ttft_ms = 95.0,
        .mean_ms = 1200.0,
        .p50_ms = 1100.0,
        .p90_ms = 1400.0,
        .tok_s = 32.0,
        .quality = 92.0,
    };

    const profiles = [_]ModelProfile{ fast_model, quality_model };
    const routed = selectProfile(&profiles, .{ .priority = .quality });
    try std.testing.expect(routed != null);
    try std.testing.expectEqualStrings("deepseek:7b", routed.?.model);
}

test "selectProfile auto heuristic handles short vs long prompts" {
    const fast_model = ModelProfile{
        .model = "mobilellm:125m",
        .backend = "ollama",
        .base_url = "http://localhost:11434",
        .runs = 3,
        .ttft_ms = 20.0,
        .mean_ms = 200.0,
        .p50_ms = 190.0,
        .p90_ms = 220.0,
        .tok_s = 80.0,
        .quality = 70.0,
    };
    const quality_model = ModelProfile{
        .model = "deepseek:7b",
        .backend = "ollama",
        .base_url = "http://localhost:11434",
        .runs = 3,
        .ttft_ms = 90.0,
        .mean_ms = 1200.0,
        .p50_ms = 1100.0,
        .p90_ms = 1400.0,
        .tok_s = 30.0,
        .quality = 95.0,
    };

    const profiles = [_]ModelProfile{ fast_model, quality_model };

    // Short prompt + small max_tokens -> auto resolves to speed
    const short_routed = selectProfile(&profiles, .{ .prompt_len = 45, .max_tokens = 64 });
    try std.testing.expect(short_routed != null);
    try std.testing.expectEqualStrings("mobilellm:125m", short_routed.?.model);

    // Long prompt -> auto resolves to quality
    const long_routed = selectProfile(&profiles, .{ .prompt_len = 1500, .max_tokens = 64 });
    try std.testing.expect(long_routed != null);
    try std.testing.expectEqualStrings("deepseek:7b", long_routed.?.model);
}
