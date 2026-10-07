const std = @import("std");
const metrics = @import("../metrics/metrics.zig");

fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| {
        try writer.writeByte(' ');
    }
}

fn writeDivider(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| {
        try writer.writeAll("─");
    }
    try writer.writeByte('\n');
}

pub fn print(
    io: std.Io,
    backend: []const u8,
    model: []const u8,
    stats: metrics.Stats,
) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const backend_col = @max(backend.len, 10);
    const model_col = @max(model.len, 26);
    // backend(backend_col) + 1 + model(model_col) + 1 + runs(4) + 2 + TTFT(8) + 2 + mean(9) + 2 + p50(9) + 2 + p90(9) + 2 + tok/s(8)
    const total_width = backend_col + 1 + model_col + 1 + 4 + 2 + 8 + 2 + 9 + 2 + 9 + 2 + 9 + 2 + 8;

    try stdout.writeByte('\n');
    try writeDivider(stdout, total_width);

    // Header
    try stdout.writeAll("backend");
    try writeSpaces(stdout, backend_col - "backend".len + 1);

    try stdout.writeAll("model");
    try writeSpaces(stdout, model_col - "model".len + 1);

    try stdout.print("{s:>4}  {s:>8}  {s:>9}  {s:>9}  {s:>9}  {s:>8}\n", .{
        "runs", "TTFT", "mean", "p50", "p90", "tok/s",
    });

    try writeDivider(stdout, total_width);

    // Data row
    try stdout.writeAll(backend);
    try writeSpaces(stdout, backend_col - backend.len + 1);

    try stdout.writeAll(model);
    try writeSpaces(stdout, model_col - model.len + 1);

    try stdout.print("{d:>4}  {d:>6.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>8.1}\n", .{
        stats.n,
        stats.p50_ttft_ms,
        stats.mean_ms,
        stats.p50_ms,
        stats.p90_ms,
        stats.mean_tok_s,
    });

    try writeDivider(stdout, total_width);
    try stdout.writeByte('\n');
    try stdout.flush();
}
