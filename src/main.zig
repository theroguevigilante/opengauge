const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");
const adapter_mod = @import("adapter/adapter.zig");
const LlamaCppAdapter = @import("adapter/llama_cpp.zig").LlamaCppAdapter;
const OllamaAdapter = @import("adapter/ollama.zig").OllamaAdapter;
const OpenAIAdapter = @import("adapter/openai.zig").OpenAIAdapter;

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    const cmd = cli.parseArgs(allocator, args) catch |err| {
        std.debug.print("error parsing arguments: {}\n\n", .{err});
        printUsage();
        return;
    };

    switch (cmd) {
        .help => printUsage(),
        .version => std.debug.print("opengauge v0.1.0\n", .{}),
        .run => |config_path| {
            defer allocator.free(config_path);

            const cfg_parsed = config.loadConfig(allocator, init.io, config_path) catch |err| {
                std.debug.print("error: failed to load config '{s}': {}\n", .{ config_path, err });
                return;
            };
            defer cfg_parsed.deinit();
            const cfg = cfg_parsed.value;

            const adp = resolveAdapter(cfg) catch |err| {
                std.debug.print("error: unknown backend '{s}': {}\n", .{ cfg.backend, err });
                return;
            };

            std.debug.print("backend: {s}  model: {s}\n", .{ cfg.backend, cfg.model });
            std.debug.print("running... ", .{});

            const resp = adp.complete(allocator, init.io, .{
                .model = cfg.model,
                .prompt = cfg.prompt,
                .max_tokens = cfg.max_tokens,
            }) catch |err| {
                std.debug.print("error: request failed: {}\n", .{err});
                return;
            };
            defer resp.deinit(allocator);

            std.debug.print("done\n\n", .{});
            std.debug.print("latency:  {}ms\n", .{resp.total_ms});
            std.debug.print("tokens:   {}\n", .{resp.tokens_generated});
            std.debug.print("tok/s:    {d:.1}\n", .{
                @as(f64, @floatFromInt(resp.tokens_generated)) /
                    (@as(f64, @floatFromInt(resp.total_ms)) / 1000.0),
            });
            std.debug.print("\nresponse:\n{s}\n", .{resp.text});
        },
    }
}

/// Resolves the adapter from the backend string in config.
/// Returns a stack-allocated Adapter vtable — the backing struct lives on the stack
/// in main and must outlive the returned Adapter.
fn resolveAdapter(cfg: config.Config) !adapter_mod.Adapter {
    if (std.mem.eql(u8, cfg.backend, "llama.cpp")) {
        var a = LlamaCppAdapter{ .base_url = cfg.base_url };
        return a.adapter();
    } else if (std.mem.eql(u8, cfg.backend, "ollama")) {
        var a = OllamaAdapter{ .base_url = cfg.base_url };
        return a.adapter();
    } else if (std.mem.eql(u8, cfg.backend, "openai")) {
        var a = OpenAIAdapter{ .base_url = cfg.base_url };
        return a.adapter();
    }
    return error.UnknownBackend;
}

fn printUsage() void {
    std.debug.print(
        \\usage: opengauge <command> [options]
        \\
        \\commands:
        \\  run <config.json>    run a benchmark using the specified config
        \\
        \\options:
        \\  -h, --help           print this help
        \\  -v, --version        print version
        \\
    , .{});
}
