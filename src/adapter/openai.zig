const std = @import("std");
const iface = @import("adapter.zig");
const TimedWriter = @import("../metrics/timer.zig").TimedWriter;

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
        stream: bool = true,
    };

    const ChatChoice = struct {
        message: Message,
    };

    const ChatResponse = struct {
        choices: []ChatChoice = &.{},
        usage: ?struct { completion_tokens: u32 } = null,
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

        var tw = TimedWriter.init(allocator, io);
        defer tw.deinit();

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
            .response_writer = &tw.writer,
        });
        const t_end = std.Io.Timestamp.now(io, .real);

        if (result.status != .ok) return error.BadHttpStatus;

        const raw_bytes = tw.written();
        var full_text = std.Io.Writer.Allocating.init(allocator);
        defer full_text.deinit();
        var tokens_generated: u32 = 0;

        // Try single-object JSON first
        if (std.json.parseFromSlice(
            ChatResponse,
            allocator,
            raw_bytes,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        )) |parsed| {
            defer parsed.deinit();
            if (parsed.value.choices.len > 0) {
                try full_text.writer.writeAll(parsed.value.choices[0].message.content);
            }
            if (parsed.value.usage) |u| {
                tokens_generated = u.completion_tokens;
            }
        } else |_| {
            // Parse SSE data lines
            var it = std.mem.splitScalar(u8, raw_bytes, '\n');
            const SseChunk = struct {
                choices: []struct {
                    delta: struct { content: ?[]const u8 = null },
                } = &.{},
                usage: ?struct { completion_tokens: u32 } = null,
            };

            while (it.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \r\t");
                if (!std.mem.startsWith(u8, trimmed, "data:")) continue;
                const json_str = std.mem.trim(u8, trimmed[5..], " \r\t");
                if (std.mem.eql(u8, json_str, "[DONE]")) break;

                const parsed = std.json.parseFromSlice(
                    SseChunk,
                    allocator,
                    json_str,
                    .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
                ) catch continue;
                defer parsed.deinit();

                if (parsed.value.choices.len > 0) {
                    if (parsed.value.choices[0].delta.content) |part| {
                        try full_text.writer.writeAll(part);
                        tokens_generated += 1;
                    }
                }
                if (parsed.value.usage) |u| {
                    tokens_generated = u.completion_tokens;
                }
            }
        }

        const ttft_ms: u64 = if (tw.first_byte_time) |fb|
            @intCast(t_start.durationTo(fb).toMilliseconds())
        else
            @intCast(t_start.durationTo(t_end).toMilliseconds());

        return .{
            .text = try allocator.dupe(u8, full_text.written()),
            .ttft_ms = ttft_ms,
            .total_ms = @intCast(t_start.durationTo(t_end).toMilliseconds()),
            .tokens_generated = tokens_generated,
        };
    }
};
