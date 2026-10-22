//! OpenGauge library root module.
const std = @import("std");

pub const config = @import("config.zig");
pub const metrics = @import("metrics/metrics.zig");
pub const timer = @import("metrics/timer.zig");
pub const profile = @import("profile.zig");
pub const cli = @import("cli.zig");
pub const table = @import("output/table.zig");
pub const router = @import("server/router.zig");

pub const adapter = struct {
    pub const Adapter = @import("adapter/adapter.zig").Adapter;
    pub const Request = @import("adapter/adapter.zig").Request;
    pub const Response = @import("adapter/adapter.zig").Response;
    pub const OllamaAdapter = @import("adapter/ollama.zig").OllamaAdapter;
    pub const LlamaCppAdapter = @import("adapter/llama_cpp.zig").LlamaCppAdapter;
    pub const OpenAIAdapter = @import("adapter/openai.zig").OpenAIAdapter;
};

test {
    _ = config;
    _ = metrics;
    _ = timer;
    _ = profile;
    _ = cli;
    _ = table;
    _ = router;
}
