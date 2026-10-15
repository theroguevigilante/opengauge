const std = @import("std");

pub const Command = union(enum) {
    run: []const u8,
    profile: void,
    help: void,
    version: void,
};

pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Command {
    if (args.len < 2) {
        return Command.help;
    }

    const cmd_str = args[1];

    if (std.mem.eql(u8, cmd_str, "run")) {
        if (args.len < 3) return error.MissingConfigPath;
        const config_path = try allocator.dupe(u8, args[2]);
        return Command{ .run = config_path };
    } else if (std.mem.eql(u8, cmd_str, "profile") or std.mem.eql(u8, cmd_str, "list")) {
        return Command.profile;
    } else if (std.mem.eql(u8, cmd_str, "--help") or std.mem.eql(u8, cmd_str, "-h")) {
        return Command.help;
    } else if (std.mem.eql(u8, cmd_str, "--version") or std.mem.eql(u8, cmd_str, "-v")) {
        return Command.version;
    }

    return error.UnknownCommand;
}

test "parseArgs recognizes run, profile, and list" {
    const allocator = std.testing.allocator;

    const run_args = [_][]const u8{ "opengauge", "run", "config.json" };
    const run_cmd = try parseArgs(allocator, &run_args);
    switch (run_cmd) {
        .run => |path| {
            try std.testing.expectEqualStrings("config.json", path);
            allocator.free(path);
        },
        else => return error.TestFailed,
    }

    const profile_args = [_][]const u8{ "opengauge", "profile" };
    const profile_cmd = try parseArgs(allocator, &profile_args);
    try std.testing.expect(profile_cmd == .profile);

    const list_args = [_][]const u8{ "opengauge", "list" };
    const list_cmd = try parseArgs(allocator, &list_args);
    try std.testing.expect(list_cmd == .profile);

    const help_args = [_][]const u8{ "opengauge", "--help" };
    const help_cmd = try parseArgs(allocator, &help_args);
    try std.testing.expect(help_cmd == .help);

    const err_args = [_][]const u8{ "opengauge", "unknown" };
    try std.testing.expectError(error.UnknownCommand, parseArgs(allocator, &err_args));
}
