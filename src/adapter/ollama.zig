const std = @import("std");
const iface = @import("adapter.zig");
const TimedWriter = @import("../metrics/timer.zig").TimedWriter;

/// Ollama HTTP adapter (POST /api/generate)
pub const OllamaAdapter = struct {
    base_url: []const u8,

    const GenerateRequest = struct {
        model: []const u8,
        prompt: []const u8,
        stream: bool = true,
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

        // Try single-object JSON first (in case server responded non-streaming)
        if (std.json.parseFromSlice(
            GenerateResponse,
            allocator,
            raw_bytes,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        )) |parsed| {
            defer parsed.deinit();
            try full_text.writer.writeAll(parsed.value.response);
            tokens_generated = parsed.value.eval_count;
        } else |_| {
            // Parse streaming NDJSON lines
            var it = std.mem.splitScalar(u8, raw_bytes, '\n');
            const Chunk = struct {
                response: ?[]const u8 = null,
                done: bool = false,
                eval_count: ?u32 = null,
            };
            while (it.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \r\t");
                if (trimmed.len == 0) continue;
                const parsed = std.json.parseFromSlice(
                    Chunk,
                    allocator,
                    trimmed,
                    .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
                ) catch continue;
                defer parsed.deinit();

                if (parsed.value.response) |part| {
                    try full_text.writer.writeAll(part);
                    if (part.len > 0) tokens_generated += 1;
                }
                if (parsed.value.eval_count) |ec| {
                    tokens_generated = ec;
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
