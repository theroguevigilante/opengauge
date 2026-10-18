const std = @import("std");
const config = @import("config.zig");
const metrics = @import("metrics/metrics.zig");

pub const ModelProfile = struct {
    model: []const u8,
    backend: []const u8,
    base_url: []const u8,
    runs: u32,
    ttft_ms: f64,
    mean_ms: f64,
    p50_ms: f64,
    p90_ms: f64,
    tok_s: f64,
    quality: ?f64 = null,
    last_tested: i64 = 0,
};

pub const Registry = struct {
    profiles: []const ModelProfile = &.{},
};

/// Resolves the path to profile.json (defaults to ~/.opengauge/profile.json)
pub fn getProfilePath(allocator: std.mem.Allocator, home_dir: ?[]const u8) ![]const u8 {
    if (home_dir) |home| {
        return std.fs.path.join(allocator, &.{ home, ".opengauge", "profile.json" });
    }
    return try allocator.dupe(u8, ".opengauge_profile.json");
}

/// Loads existing profiles from disk. If the file does not exist, returns an empty Registry.
pub fn loadProfiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !std.json.Parsed(Registry) {
    const buffer = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, @enumFromInt(std.math.maxInt(usize))) catch |err| {
        if (err == error.FileNotFound) {
            // Return empty registry parsed from "{}"
            return std.json.parseFromSlice(Registry, allocator, "{}", .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            });
        }
        return err;
    };
    defer allocator.free(buffer);

    return std.json.parseFromSlice(Registry, allocator, buffer, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

/// Upserts a model's benchmark results directly to a given file path.
pub fn saveOrUpdateProfileAtPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    profile_path: []const u8,
    cfg: config.Config,
    stats: metrics.Stats,
) !void {
    const existing = try loadProfiles(allocator, io, profile_path);
    defer existing.deinit();

    const now_ts: i64 = @divTrunc(std.Io.Timestamp.now(io, .real).toMilliseconds(), 1000);

    const new_entry = ModelProfile{
        .model = cfg.model,
        .backend = cfg.backend,
        .base_url = cfg.base_url,
        .runs = stats.n,
        .ttft_ms = stats.p50_ttft_ms,
        .mean_ms = stats.mean_ms,
        .p50_ms = stats.p50_ms,
        .p90_ms = stats.p90_ms,
        .tok_s = stats.mean_tok_s,
        .quality = stats.mean_quality,
        .last_tested = now_ts,
    };

    var list: std.ArrayList(ModelProfile) = .empty;
    defer list.deinit(allocator);

    var updated = false;
    for (existing.value.profiles) |p| {
        if (std.mem.eql(u8, p.model, cfg.model) and std.mem.eql(u8, p.backend, cfg.backend)) {
            try list.append(allocator, new_entry);
            updated = true;
        } else {
            try list.append(allocator, p);
        }
    }

    if (!updated) {
        try list.append(allocator, new_entry);
    }

    const reg = Registry{ .profiles = list.items };
    const json_bytes = try std.json.Stringify.valueAlloc(allocator, reg, .{ .whitespace = .indent_2 });
    defer allocator.free(json_bytes);

    // Ensure parent directory exists if present
    if (std.fs.path.dirname(profile_path)) |dir_name| {
        if (dir_name.len > 0) {
            std.Io.Dir.cwd().createDirPath(io, dir_name) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }
    }

    const file = try std.Io.Dir.cwd().createFile(io, profile_path, .{});
    defer file.close(io);

    var file_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &file_buffer);
    try file_writer.interface.writeAll(json_bytes);
    try file_writer.interface.flush();
}

/// Upserts a model's benchmark results into ~/.opengauge/profile.json.
pub fn saveOrUpdateProfile(
    allocator: std.mem.Allocator,
    io: std.Io,
    home_dir: ?[]const u8,
    cfg: config.Config,
    stats: metrics.Stats,
) !void {
    const profile_path = try getProfilePath(allocator, home_dir);
    defer allocator.free(profile_path);

    try saveOrUpdateProfileAtPath(allocator, io, profile_path, cfg, stats);
}

test "Registry JSON serialization and deserialization" {
    const test_json =
        \\{
        \\  "profiles": [
        \\    {
        \\      "model": "smollm2:135m",
        \\      "backend": "ollama",
        \\      "base_url": "http://localhost:11434",
        \\      "runs": 3,
        \\      "ttft_ms": 27.0,
        \\      "mean_ms": 500.0,
        \\      "p50_ms": 480.0,
        \\      "p90_ms": 600.0,
        \\      "tok_s": 50.0,
        \\      "quality": 84.0,
        \\      "last_tested": 1000
        \\    }
        \\  ]
        \\}
    ;

    const parsed = try std.json.parseFromSlice(Registry, std.testing.allocator, test_json, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.value.profiles.len);
    const p = parsed.value.profiles[0];
    try std.testing.expectEqualStrings("smollm2:135m", p.model);
    try std.testing.expectEqualStrings("ollama", p.backend);
    try std.testing.expectApproxEqAbs(@as(f64, 27.0), p.ttft_ms, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 84.0), p.quality.?, 0.01);
}

test "saveOrUpdateProfileAtPath creates and updates entries" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/test_profile.json", .{tmp.sub_path});
    defer allocator.free(tmp_path);

    const cfg1 = config.Config{
        .model = "test-model-1",
        .backend = "ollama",
        .base_url = "http://localhost:11434",
        .prompt = "test prompt",
    };

    var results1 = [_]metrics.RunResult{
        .{ .ttft_ms = 20, .total_ms = 100, .tokens_generated = 10, .quality_score = 80 },
    };
    const stats1 = metrics.Stats.compute(&results1);

    // 1. Initial write
    try saveOrUpdateProfileAtPath(allocator, io, tmp_path, cfg1, stats1);

    const loaded1 = try loadProfiles(allocator, io, tmp_path);
    defer loaded1.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded1.value.profiles.len);
    try std.testing.expectEqualStrings("test-model-1", loaded1.value.profiles[0].model);
    try std.testing.expectApproxEqAbs(@as(f64, 80.0), loaded1.value.profiles[0].quality.?, 0.01);

    // 2. Update existing model with new quality score
    var results2 = [_]metrics.RunResult{
        .{ .ttft_ms = 15, .total_ms = 80, .tokens_generated = 10, .quality_score = 95 },
    };
    const stats2 = metrics.Stats.compute(&results2);
    try saveOrUpdateProfileAtPath(allocator, io, tmp_path, cfg1, stats2);

    const loaded2 = try loadProfiles(allocator, io, tmp_path);
    defer loaded2.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded2.value.profiles.len);
    try std.testing.expectApproxEqAbs(@as(f64, 95.0), loaded2.value.profiles[0].quality.?, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), loaded2.value.profiles[0].ttft_ms, 0.01);

    // 3. Add second distinct model
    const cfg2 = config.Config{
        .model = "test-model-2",
        .backend = "llama.cpp",
        .base_url = "http://localhost:8080",
        .prompt = "test prompt 2",
    };
    try saveOrUpdateProfileAtPath(allocator, io, tmp_path, cfg2, stats1);

    const loaded3 = try loadProfiles(allocator, io, tmp_path);
    defer loaded3.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded3.value.profiles.len);
}
