const std = @import("std");
const iface = @import("adapter.zig");

/// llama.cpp HTTP server adapter (POST /v1/completions)
pub const LlamaCppAdapter = struct {
    base_url: []const u8,

    const CompletionRequest = struct {
        model: []const u8,
        prompt: []const u8,
        max_tokens: u32,
        stream: bool = false,
    };

    const CompletionChoice = struct {
        text: []const u8,
    };

    const CompletionResponse = struct {
        choices: []CompletionChoice,
        usage: struct { completion_tokens: u32 },
    };

    pub fn adapter(self: *LlamaCppAdapter) iface.Adapter {
        return .{ .ptr = self, .completeFn = complete };
    }

    fn complete(ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io, req: iface.Request) anyerror!iface.Response {
        
        const self: *LlamaCppAdapter = @ptrCast(@alignCast(ptr));

        const url = try std.fmt.allocPrint(allocator, "{s}/v1/completions", .{self.base_url});
        defer allocator.free(url);

        const body = try std.json.Stringify.valueAlloc(allocator, CompletionRequest{
            .model = req.model,
            .prompt = req.prompt,
            .max_tokens = req.max_tokens,
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
            CompletionResponse,
            allocator,
            response_aw.written(),
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return error.NoChoicesInResponse;

        return .{
            .text = try allocator.dupe(u8, parsed.value.choices[0].text),
            .total_ms = @intCast(t_start.durationTo(t_end).toMilliseconds()),
            .tokens_generated = parsed.value.usage.completion_tokens,
        };
    }
};
