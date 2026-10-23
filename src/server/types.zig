const std = @import("std");
const router = @import("router.zig");

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
};

pub const ChatCompletionRequest = struct {
    model: []const u8 = "auto",
    messages: []const ChatMessage = &.{},
    max_tokens: ?u32 = null,
    temperature: ?f64 = null,
    stream: bool = false,
};

/// Parses an OpenAI-compatible POST /v1/chat/completions JSON payload.
pub fn parseChatCompletionRequest(
    allocator: std.mem.Allocator,
    json_bytes: []const u8,
) !std.json.Parsed(ChatCompletionRequest) {
    return std.json.parseFromSlice(ChatCompletionRequest, allocator, json_bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

/// Computes the total prompt length in bytes across all message contents without allocating.
pub fn estimatePromptLength(messages: []const ChatMessage) usize {
    var total: usize = 0;
    for (messages) |msg| {
        total += msg.content.len;
    }
    return total;
}

/// Formats the chat messages into a consolidated prompt string.
pub fn extractFullPrompt(allocator: std.mem.Allocator, messages: []const ChatMessage) ![]const u8 {
    if (messages.len == 0) return try allocator.dupe(u8, "");
    if (messages.len == 1) return try allocator.dupe(u8, messages[0].content);

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    for (messages, 0..) |msg, i| {
        if (i > 0) try list.appendSlice(allocator, "\n\n");
        try list.appendSlice(allocator, msg.role);
        try list.appendSlice(allocator, ": ");
        try list.appendSlice(allocator, msg.content);
    }

    return list.toOwnedSlice(allocator);
}

/// Converts a ChatCompletionRequest and optional header into RouteCriteria for router.selectProfile.
pub fn toRouteCriteria(req: ChatCompletionRequest, priority_header: ?[]const u8) router.RouteCriteria {
    var priority: router.Priority = .auto;

    if (priority_header) |hdr| {
        if (hdr.len > 0) {
            priority = router.Priority.fromString(hdr);
        }
    }

    // If header didn't specify priority, check if model field requests "speed" or "quality"
    if (priority == .auto) {
        if (std.ascii.eqlIgnoreCase(req.model, "speed")) {
            priority = .speed;
        } else if (std.ascii.eqlIgnoreCase(req.model, "quality")) {
            priority = .quality;
        }
    }

    return .{
        .prompt_len = estimatePromptLength(req.messages),
        .max_tokens = req.max_tokens,
        .priority = priority,
    };
}

// OpenAI Model List types for GET /v1/models
pub const ModelInfo = struct {
    id: []const u8,
    object: []const u8 = "model",
    created: i64 = 0,
    owned_by: []const u8 = "opengauge",
};

pub const ModelListResponse = struct {
    object: []const u8 = "list",
    data: []const ModelInfo,
};

test "parseChatCompletionRequest parses valid JSON" {
    const allocator = std.testing.allocator;
    const json_str =
        \\{
        \\  "model": "auto",
        \\  "messages": [
        \\    {"role": "system", "content": "You are a code assistant."},
        \\    {"role": "user", "content": "Fix the compiler error."}
        \\  ],
        \\  "max_tokens": 256,
        \\  "temperature": 0.5,
        \\  "stream": true,
        \\  "top_p": 1.0,
        \\  "presence_penalty": 0.0
        \\}
    ;

    const parsed = try parseChatCompletionRequest(allocator, json_str);
    defer parsed.deinit();

    const req = parsed.value;
    try std.testing.expectEqualStrings("auto", req.model);
    try std.testing.expectEqual(@as(usize, 2), req.messages.len);
    try std.testing.expectEqualStrings("system", req.messages[0].role);
    try std.testing.expectEqualStrings("You are a code assistant.", req.messages[0].content);
    try std.testing.expectEqualStrings("user", req.messages[1].role);
    try std.testing.expectEqualStrings("Fix the compiler error.", req.messages[1].content);
    try std.testing.expectEqual(@as(u32, 256), req.max_tokens.?);
    try std.testing.expect(req.stream == true);

    // Prompt length
    const total_len = estimatePromptLength(req.messages);
    try std.testing.expectEqual("You are a code assistant.".len + "Fix the compiler error.".len, total_len);

    // Full prompt extraction
    const full_prompt = try extractFullPrompt(allocator, req.messages);
    defer allocator.free(full_prompt);
    try std.testing.expectEqualStrings(
        "system: You are a code assistant.\n\nuser: Fix the compiler error.",
        full_prompt,
    );
}

test "toRouteCriteria resolves priority from model and header" {
    const messages = [_]ChatMessage{
        .{ .role = "user", .content = "hello" },
    };

    // 1. Model field requests speed
    const req_speed = ChatCompletionRequest{
        .model = "speed",
        .messages = &messages,
        .max_tokens = 64,
    };
    const crit1 = toRouteCriteria(req_speed, null);
    try std.testing.expectEqual(router.Priority.speed, crit1.priority);
    try std.testing.expectEqual(@as(usize, 5), crit1.prompt_len);
    try std.testing.expectEqual(@as(u32, 64), crit1.max_tokens.?);

    // 2. Header overrides model field
    const req_auto = ChatCompletionRequest{
        .model = "speed",
        .messages = &messages,
        .max_tokens = 64,
    };
    const crit2 = toRouteCriteria(req_auto, "quality");
    try std.testing.expectEqual(router.Priority.quality, crit2.priority);

    // 3. Default to auto
    const req_plain = ChatCompletionRequest{
        .model = "llama-3-8b",
        .messages = &messages,
    };
    const crit3 = toRouteCriteria(req_plain, null);
    try std.testing.expectEqual(router.Priority.auto, crit3.priority);
}
