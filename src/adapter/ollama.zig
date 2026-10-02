const std = @import("std");
const iface = @import("adapter.zig");

/// Ollama HTTP adapter (POST /api/generate)
pub const OllamaAdapter = struct {
    base_url: []const u8,

    const GenerateRequest = struct {
        model: []const u8,
        prompt: []const u8,
        stream: bool = false,
        options: struct { num_predict: u32 },
    };

    const GenerateResponse = struct {
        response: []const u8,
        eval_count: u32,
    };

    pub fn adapter(self: *OllamaAdapter) iface.Adapter {
        return .{ .ptr = self, .completeFn = complete };
    }

    fn complete(ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io, req: iface.Request) anyerror!iface.Response {
        
        const self: *OllamaAdapter = @ptrCast(@alignCast(ptr));

        const url = try std.fmt.allocPrint(allocator, "{s}/api/generate", .{self.base_url});
        defer allocator.free(url);

        const body = try std.json.Stringify.valueAlloc(allocator, GenerateRequest{
            .model = req.model,
            .prompt = req.prompt,
            .options = .{ .num_predict = req.max_tokens },
        }, .{});
        defer allocator.free(body);

        var response_aw = std.Io.Writer.Allocating.init(allocator);
        defer response_aw.deinit();

        var client: std.http.Client = .{ .allocator = allocator, .io = io };
        defer client.deinit();

        const t_start = std.Io.Timestamp.now(io, .real);
        const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
            .response_writer = &response_aw.writer,
        });
        const t_end = std.Io.Timestamp.now(io, .real);

        if (result.status != .ok) return error.BadHttpStatus;

        const parsed = try std.json.parseFromSlice(
            GenerateResponse,
            allocator,
            response_aw.written(),
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        defer parsed.deinit();

        return .{
            .text = try allocator.dupe(u8, parsed.value.response),
            .total_ms = @intCast(t_start.durationTo(t_end).toMilliseconds()),
            .tokens_generated = parsed.value.eval_count,
        };
    }
};
