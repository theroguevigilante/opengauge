const std = @import("std");
const iface = @import("adapter.zig");

/// Generic OpenAI-compatible HTTP adapter (POST /v1/chat/completions)
pub const OpenAIAdapter = struct {
    base_url: []const u8,
    api_key: ?[]const u8 = null,

    const Message = struct {
        role: []const u8,
        content: []const u8,
    };

    const ChatRequest = struct {
        model: []const u8,
        messages: []const Message,
        max_tokens: u32,
        stream: bool = false,
    };

    const ChatChoice = struct {
        message: Message,
    };

    const ChatResponse = struct {
        choices: []ChatChoice,
        usage: struct { completion_tokens: u32 },
    };

    pub fn adapter(self: *OpenAIAdapter) iface.Adapter {
        return .{ .ptr = self, .completeFn = complete };
    }

    fn complete(ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io, req: iface.Request) anyerror!iface.Response {
        
        const self: *OpenAIAdapter = @ptrCast(@alignCast(ptr));

        const url = try std.fmt.allocPrint(allocator, "{s}/v1/chat/completions", .{self.base_url});
        defer allocator.free(url);

        const messages = [_]Message{.{ .role = "user", .content = req.prompt }};
        const body = try std.json.Stringify.valueAlloc(allocator, ChatRequest{
            .model = req.model,
            .messages = &messages,
            .max_tokens = req.max_tokens,
        }, .{});
        defer allocator.free(body);

        var response_aw = std.Io.Writer.Allocating.init(allocator);
        defer response_aw.deinit();

        var client: std.http.Client = .{ .allocator = allocator, .io = io };
        defer client.deinit();

        // Conditionally add Authorization header
        var extra_headers_buf: [2]std.http.Header = undefined;
        extra_headers_buf[0] = .{ .name = "Content-Type", .value = "application/json" };
        var auth_buf: [256]u8 = undefined;
        const extra_headers: []const std.http.Header = if (self.api_key) |key| blk: {
            const auth = try std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{key});
            extra_headers_buf[1] = .{ .name = "Authorization", .value = auth };
            break :blk extra_headers_buf[0..2];
        } else extra_headers_buf[0..1];

        const t_start = std.Io.Timestamp.now(io, .real);
        const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body,
            .extra_headers = extra_headers,
            .response_writer = &response_aw.writer,
        });
        const t_end = std.Io.Timestamp.now(io, .real);

        if (result.status != .ok) return error.BadHttpStatus;

        const parsed = try std.json.parseFromSlice(
            ChatResponse,
            allocator,
            response_aw.written(),
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return error.NoChoicesInResponse;

        return .{
            .text = try allocator.dupe(u8, parsed.value.choices[0].message.content),
            .total_ms = @intCast(t_start.durationTo(t_end).toMilliseconds()),
            .tokens_generated = parsed.value.usage.completion_tokens,
        };
    }
};
