const std = @import("std");

pub const Config = struct {
    model: []const u8,
    backend: []const u8,
    base_url: []const u8,
    prompt: []const u8,
    max_tokens: u32 = 512,
    metrics: []const []const u8,
};

pub fn loadConfig(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !std.json.Parsed(Config) {
    const buffer = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, @enumFromInt(std.math.maxInt(usize)));
    defer allocator.free(buffer);

    return std.json.parseFromSlice(Config, allocator, buffer, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}
