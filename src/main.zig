const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Accessing command line arguments in Zig 0.16.0
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    const cmd = cli.parseArgs(allocator, args) catch |err| {
        std.debug.print("Error parsing arguments: {}\n\n", .{err});
        printUsage();
        return;
    };

    switch (cmd) {
        .help => {
            printUsage();
        },
        .version => {
            std.debug.print("OpenGauge v0.1.0\n", .{});
        },
        .run => |config_path| {
            defer allocator.free(config_path);
            std.debug.print("Starting OpenGauge run...\n", .{});
            std.debug.print("Loading config from: {s}\n", .{config_path});

            const cfg_parsed = config.loadConfig(allocator, init.io, config_path) catch |err| {
                std.debug.print("Failed to load config '{s}': {}\n", .{config_path, err});
                return;
            };
            defer cfg_parsed.deinit();
            
            const cfg = cfg_parsed.value;
            std.debug.print("\nLoaded Config:\n  Model: {s}\n  Backend: {s}\n  Prompt: {s}\n  Metrics: {d} to collect\n", .{
                cfg.model,
                cfg.backend,
                cfg.prompt,
                cfg.metrics.len,
            });
        },
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: opengauge <command> [options]
        \\
        \\Commands:
        \\  run <config.json>    Start a benchmark run using the specified configuration
        \\
        \\Options:
        \\  -h, --help           Print command-specific usage
        \\  -v, --version        Print version information
        \\
        , .{});
}
