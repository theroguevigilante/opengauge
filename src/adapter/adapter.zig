const std = @import("std");

pub const Request = struct {
    model: []const u8,
    prompt: []const u8,
    max_tokens: u32 = 512,
};

pub const Response = struct {
    text: []const u8,
    ttft_ms: u64,
    total_ms: u64,
    tokens_generated: u32,

    pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

/// Vtable-based adapter interface. Each backend implements completeFn.
pub const Adapter = struct {
    ptr: *anyopaque,
    completeFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io, req: Request) anyerror!Response,

    pub fn complete(self: Adapter, allocator: std.mem.Allocator, io: std.Io, req: Request) !Response {
        return self.completeFn(self.ptr, allocator, io, req);
    }
};
