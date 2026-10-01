const std = @import("std");

pub const Command = union(enum) {
    run: []const u8,
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
    } else if (std.mem.eql(u8, cmd_str, "--help") or std.mem.eql(u8, cmd_str, "-h")) {
        return Command.help;
    } else if (std.mem.eql(u8, cmd_str, "--version") or std.mem.eql(u8, cmd_str, "-v")) {
        return Command.version;
    }

    return error.UnknownCommand;
}
