const std = @import("std");
const metrics = @import("../metrics/metrics.zig");
const profile_mod = @import("../profile.zig");

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
    const quality_extra: usize = if (stats.mean_quality != null) 2 + 9 else 0;
    // backend(backend_col) + 1 + model(model_col) + 1 + runs(4) + 2 + TTFT(8) + 2 + mean(9) + 2 + p50(9) + 2 + p90(9) + 2 + tok/s(8) + quality_extra
    const total_width = backend_col + 1 + model_col + 1 + 4 + 2 + 8 + 2 + 9 + 2 + 9 + 2 + 9 + 2 + 8 + quality_extra;

    try stdout.writeByte('\n');
    try writeDivider(stdout, total_width);

    // Header
    try stdout.writeAll("backend");
    try writeSpaces(stdout, backend_col - "backend".len + 1);

    try stdout.writeAll("model");
    try writeSpaces(stdout, model_col - "model".len + 1);

    if (stats.mean_quality != null) {
        try stdout.print("{s:>4}  {s:>8}  {s:>9}  {s:>9}  {s:>9}  {s:>8}  {s:>9}\n", .{
            "runs", "TTFT", "mean", "p50", "p90", "tok/s", "quality",
        });
    } else {
        try stdout.print("{s:>4}  {s:>8}  {s:>9}  {s:>9}  {s:>9}  {s:>8}\n", .{
            "runs", "TTFT", "mean", "p50", "p90", "tok/s",
        });
    }

    try writeDivider(stdout, total_width);

    // Data row
    try stdout.writeAll(backend);
    try writeSpaces(stdout, backend_col - backend.len + 1);

    try stdout.writeAll(model);
    try writeSpaces(stdout, model_col - model.len + 1);

    if (stats.mean_quality) |q| {
        try stdout.print("{d:>4}  {d:>6.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>8.1}  {d:>5.0}/100\n", .{
            stats.n,
            stats.p50_ttft_ms,
            stats.mean_ms,
            stats.p50_ms,
            stats.p90_ms,
            stats.mean_tok_s,
            q,
        });
    } else {
        try stdout.print("{d:>4}  {d:>6.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>8.1}\n", .{
            stats.n,
            stats.p50_ttft_ms,
            stats.mean_ms,
            stats.p50_ms,
            stats.p90_ms,
            stats.mean_tok_s,
        });
    }

    try writeDivider(stdout, total_width);
    try stdout.writeByte('\n');
    try stdout.flush();
}

pub fn printProfiles(
    io: std.Io,
    profiles: []const profile_mod.ModelProfile,
) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (profiles.len == 0) {
        try stdout.print("\nNo model profiles found in registry. Run a benchmark first.\n\n", .{});
        try stdout.flush();
        return;
    }

    var max_backend: usize = 10;
    var max_model: usize = 26;
    var has_quality = false;

    for (profiles) |p| {
        max_backend = @max(max_backend, p.backend.len);
        max_model = @max(max_model, p.model.len);
        if (p.quality != null) has_quality = true;
    }

    const quality_extra: usize = if (has_quality) 2 + 9 else 0;
    const total_width = max_backend + 1 + max_model + 1 + 4 + 2 + 8 + 2 + 9 + 2 + 9 + 2 + 9 + 2 + 8 + quality_extra;

    try stdout.writeByte('\n');
    try writeDivider(stdout, total_width);

    // Header
    try stdout.writeAll("backend");
    try writeSpaces(stdout, max_backend - "backend".len + 1);

    try stdout.writeAll("model");
    try writeSpaces(stdout, max_model - "model".len + 1);

    if (has_quality) {
        try stdout.print("{s:>4}  {s:>8}  {s:>9}  {s:>9}  {s:>9}  {s:>8}  {s:>9}\n", .{
            "runs", "TTFT", "mean", "p50", "p90", "tok/s", "quality",
        });
    } else {
        try stdout.print("{s:>4}  {s:>8}  {s:>9}  {s:>9}  {s:>9}  {s:>8}\n", .{
            "runs", "TTFT", "mean", "p50", "p90", "tok/s",
        });
    }

    try writeDivider(stdout, total_width);

    // Data rows
    for (profiles) |p| {
        try stdout.writeAll(p.backend);
        try writeSpaces(stdout, max_backend - p.backend.len + 1);

        try stdout.writeAll(p.model);
        try writeSpaces(stdout, max_model - p.model.len + 1);

        if (has_quality) {
            if (p.quality) |q| {
                try stdout.print("{d:>4}  {d:>6.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>8.1}  {d:>5.0}/100\n", .{
                    p.runs,
                    p.ttft_ms,
                    p.mean_ms,
                    p.p50_ms,
                    p.p90_ms,
                    p.tok_s,
                    q,
                });
            } else {
                try stdout.print("{d:>4}  {d:>6.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>8.1}  {s:>9}\n", .{
                    p.runs,
                    p.ttft_ms,
                    p.mean_ms,
                    p.p50_ms,
                    p.p90_ms,
                    p.tok_s,
                    "-",
                });
            }
        } else {
            try stdout.print("{d:>4}  {d:>6.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>7.0}ms  {d:>8.1}\n", .{
                p.runs,
                p.ttft_ms,
                p.mean_ms,
                p.p50_ms,
                p.p90_ms,
                p.tok_s,
            });
        }
    }

    try writeDivider(stdout, total_width);
    try stdout.writeByte('\n');
    try stdout.flush();
}
