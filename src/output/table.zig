const std = @import("std");
const metrics = @import("../metrics/metrics.zig");

const DIVIDER = "─" ** 72;

pub fn print(
    io: std.Io,
    backend: []const u8,
    model: []const u8,
    stats: metrics.Stats,
) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("\n{s}\n", .{DIVIDER});
    try stdout.print("{s:<12} {s:<26} {s:>4}  {s:>9}  {s:>9}  {s:>9}  {s:>8}\n", .{
        "backend", "model", "runs", "mean", "p50", "p90", "tok/s",
    });
    try stdout.print("{s}\n", .{DIVIDER});
    try stdout.print("{s:<12} {s:<26} {d:>4}  {d:>7.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>7.1}\n", .{
        backend,
        model,
        stats.n,
        stats.mean_ms,
        stats.p50_ms,
        stats.p90_ms,
        stats.mean_tok_s,
    });
    try stdout.print("{s}\n\n", .{DIVIDER});
    try stdout.flush();
}
