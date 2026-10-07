const std = @import("std");
const iface = @import("adapter.zig");
const TimedWriter = @import("../metrics/timer.zig").TimedWriter;

/// llama.cpp HTTP server adapter (POST /v1/completions)
pub const LlamaCppAdapter = struct {
    base_url: []const u8,

    const CompletionRequest = struct {
        model: []const u8,
        prompt: []const u8,
        max_tokens: u32,
        stream: bool = true,
    };

    const CompletionChoice = struct {
        text: []const u8,
    };

    const CompletionResponse = struct {
        choices: []CompletionChoice = &.{},
        usage: ?struct { completion_tokens: u32 } = null,
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

        var tw = TimedWriter.init(allocator, io);
        defer tw.deinit();

        var client: std.http.Client = .{ .allocator = allocator, .io = io };
        defer client.deinit();

        const t_start = std.Io.Timestamp.now(io, .real);
        const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
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
            CompletionResponse,
            allocator,
            raw_bytes,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        )) |parsed| {
            defer parsed.deinit();
            if (parsed.value.choices.len > 0) {
                try full_text.writer.writeAll(parsed.value.choices[0].text);
            }
            if (parsed.value.usage) |u| {
                tokens_generated = u.completion_tokens;
            }
        } else |_| {
            // Parse SSE data lines
            var it = std.mem.splitScalar(u8, raw_bytes, '\n');
            const SseChunk = struct {
                choices: []CompletionChoice = &.{},
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
                    try full_text.writer.writeAll(parsed.value.choices[0].text);
                    tokens_generated += 1;
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
