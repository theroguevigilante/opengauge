const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");
const adapter_mod = @import("adapter/adapter.zig");
const LlamaCppAdapter = @import("adapter/llama_cpp.zig").LlamaCppAdapter;
const OllamaAdapter = @import("adapter/ollama.zig").OllamaAdapter;
const OpenAIAdapter = @import("adapter/openai.zig").OpenAIAdapter;
const metrics = @import("metrics/metrics.zig");
const table = @import("output/table.zig");
const profile = @import("profile.zig");

fn evaluateResponse(
    allocator: std.mem.Allocator,
    io: std.Io,
    evaluator_url: []const u8,
    prompt: []const u8,
    response_text: []const u8,
) !u32 {
    const Payload = struct {
        prompt: []const u8,
        response: []const u8,
    };

    const body = try std.json.Stringify.valueAlloc(allocator, Payload{
        .prompt = prompt,
        .response = response_text,
    }, .{});
    defer allocator.free(body);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var resp_writer = std.Io.Writer.Allocating.init(allocator);
    defer resp_writer.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = evaluator_url },
        .method = .POST,
        .payload = body,
        .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
        .response_writer = &resp_writer.writer,
    });

    if (result.status != .ok) return error.EvaluatorFailed;

    const raw_bytes = resp_writer.written();
    const ScoreResponse = struct {
        score: u32,
    };

    const parsed = try std.json.parseFromSlice(ScoreResponse, allocator, raw_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return parsed.value.score;
}

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    const cmd = cli.parseArgs(allocator, args) catch |err| {
        try stderr.print("error parsing arguments: {}\n\n", .{err});
        try stderr.flush();
        printUsage();
        return;
    };

    switch (cmd) {
        .help => printUsage(),
        .version => {
            var stdout_buffer: [256]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("opengauge v0.1.0\n", .{});
            try stdout.flush();
        },
        .profile => {
            const home_dir = init.environ_map.get("HOME");
            const profile_path = profile.getProfilePath(allocator, home_dir) catch |err| {
                try stderr.print("error: failed to resolve profile path: {}\n", .{err});
                try stderr.flush();
                return;
            };
            defer allocator.free(profile_path);

            const registry = profile.loadProfiles(allocator, init.io, profile_path) catch |err| {
                try stderr.print("error: failed to load profiles from '{s}': {}\n", .{ profile_path, err });
                try stderr.flush();
                return;
            };
            defer registry.deinit();

            try table.printProfiles(init.io, registry.value.profiles);
        },
        .run => |config_path| {
            defer allocator.free(config_path);

            const cfg_parsed = config.loadConfig(allocator, init.io, config_path) catch |err| {
                try stderr.print("error: failed to load config '{s}': {}\n", .{ config_path, err });
                try stderr.flush();
                return;
            };
            defer cfg_parsed.deinit();
            const cfg = cfg_parsed.value;

            if (cfg.runs == 0) {
                try stderr.print("error: runs must be >= 1\n", .{});
                try stderr.flush();
                return;
            }

            // Build the adapter. BackendStorage keeps the backing struct alive
            // for the duration of this scope, so Adapter.ptr is never dangling.
            const BackendStorage = union(enum) {
                llama_cpp: LlamaCppAdapter,
                ollama: OllamaAdapter,
                openai: OpenAIAdapter,
            };

            var storage: BackendStorage = if (std.mem.eql(u8, cfg.backend, "llama.cpp"))
                .{ .llama_cpp = .{ .base_url = cfg.base_url } }
            else if (std.mem.eql(u8, cfg.backend, "ollama"))
                .{ .ollama = .{ .base_url = cfg.base_url } }
            else if (std.mem.eql(u8, cfg.backend, "openai"))
                .{ .openai = .{ .base_url = cfg.base_url } }
            else {
                try stderr.print("error: unknown backend '{s}'\n", .{cfg.backend});
                try stderr.flush();
                return;
            };

            const adp: adapter_mod.Adapter = switch (storage) {
                .llama_cpp => |*a| a.adapter(),
                .ollama => |*a| a.adapter(),
                .openai => |*a| a.adapter(),
            };

            const req: adapter_mod.Request = .{
                .model = cfg.model,
                .prompt = cfg.prompt,
                .max_tokens = cfg.max_tokens,
            };

            // Warmup runs — results discarded
            if (cfg.warmup > 0) {
                try stderr.print("warming up ({d} run(s))...\n", .{cfg.warmup});
                try stderr.flush();
                for (0..cfg.warmup) |_| {
                    const resp = adp.complete(allocator, init.io, req) catch |err| {
                        try stderr.print("error: warmup request failed: {}\n", .{err});
                        try stderr.flush();
                        return;
                    };
                    resp.deinit(allocator);
                }
            }

            // Timed runs
            try stderr.print("running {d} benchmark run(s)...\n", .{cfg.runs});
            try stderr.flush();

            const results = try allocator.alloc(metrics.RunResult, cfg.runs);
            defer allocator.free(results);

            for (results, 0..) |*slot, i| {
                try stderr.print("  run {d}/{d}\r", .{ i + 1, cfg.runs });
                try stderr.flush();
                const resp = adp.complete(allocator, init.io, req) catch |err| {
                    try stderr.print("\nerror: run {d} failed: {}\n", .{ i + 1, err });
                    try stderr.flush();
                    return;
                };
                defer resp.deinit(allocator);

                var quality_score: ?u32 = null;
                if (cfg.evaluator) |ev| {
                    quality_score = evaluateResponse(allocator, init.io, ev.url, cfg.prompt, resp.text) catch |err| blk: {
                        try stderr.print("\nwarning: evaluator failed on run {d}: {}\n", .{ i + 1, err });
                        break :blk null;
                    };
                }

                slot.* = .{
                    .ttft_ms = resp.ttft_ms,
                    .total_ms = resp.total_ms,
                    .tokens_generated = resp.tokens_generated,
                    .quality_score = quality_score,
                };
            }
            try stderr.print("\n", .{});
            try stderr.flush();

            const stats = metrics.Stats.compute(results);
            try table.print(init.io, cfg.backend, cfg.model, stats);

            const home_dir = init.environ_map.get("HOME");
            profile.saveOrUpdateProfile(allocator, init.io, home_dir, cfg, stats) catch |err| {
                try stderr.print("warning: failed to save profile: {}\n", .{err});
                try stderr.flush();
            };
        },
    }
}

fn printUsage() void {
    std.debug.print(
        \\usage: opengauge <command> [options]
        \\
        \\commands:
        \\  run <config.json>    run a benchmark using the specified config
        \\  profile, list        display the benchmarked model profiles leaderboard
        \\
        \\options:
        \\  -h, --help           print this help
        \\  -v, --version        print version
        \\
    , .{});
}

test {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("metrics/metrics.zig");
    _ = @import("metrics/timer.zig");
    _ = @import("profile.zig");
}
