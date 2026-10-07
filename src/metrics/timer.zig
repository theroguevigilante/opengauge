const std = @import("std");

/// A Writer that captures the exact timestamp when the first byte arrives,
/// while delegating all storage to standard Allocating writer.
pub const TimedWriter = struct {
    allocating: std.Io.Writer.Allocating,
    writer: std.Io.Writer,
    io: std.Io,
    first_byte_time: ?std.Io.Timestamp = null,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .sendFile = sendFile,
        .flush = flush,
        .rebase = rebase,
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io) TimedWriter {
        return .{
            .allocating = std.Io.Writer.Allocating.init(allocator),
            .writer = .{
                .vtable = &vtable,
                .buffer = &.{},
            },
            .io = io,
            .first_byte_time = null,
        };
    }

    pub fn deinit(self: *TimedWriter) void {
        self.allocating.deinit();
    }

    pub fn written(self: *TimedWriter) []u8 {
        return self.allocating.written();
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *TimedWriter = @alignCast(@fieldParentPtr("writer", w));
        if (self.first_byte_time == null) {
            self.first_byte_time = std.Io.Timestamp.now(self.io, .real);
        }
        return self.allocating.writer.vtable.drain(&self.allocating.writer, data, splat);
    }

    fn sendFile(w: *std.Io.Writer, file_reader: *std.Io.File.Reader, limit: std.Io.Limit) std.Io.Writer.FileError!usize {
        const self: *TimedWriter = @alignCast(@fieldParentPtr("writer", w));
        if (self.first_byte_time == null) {
            self.first_byte_time = std.Io.Timestamp.now(self.io, .real);
        }
        return self.allocating.writer.vtable.sendFile(&self.allocating.writer, file_reader, limit);
    }

    fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *TimedWriter = @alignCast(@fieldParentPtr("writer", w));
        return self.allocating.writer.vtable.flush(&self.allocating.writer);
    }

    fn rebase(w: *std.Io.Writer, preserve: usize, minimum_len: usize) std.Io.Writer.Error!void {
        const self: *TimedWriter = @alignCast(@fieldParentPtr("writer", w));
        return self.allocating.writer.vtable.rebase(&self.allocating.writer, preserve, minimum_len);
    }
};

test "TimedWriter captures first byte timestamp and buffers output" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tw = TimedWriter.init(allocator, io);
    defer tw.deinit();

    try std.testing.expect(tw.first_byte_time == null);

    try tw.writer.writeAll("hello ");
    try std.testing.expect(tw.first_byte_time != null);
    const first_ts = tw.first_byte_time.?;

    try tw.writer.writeAll("world");
    // Ensure timestamp was not overwritten on subsequent write
    try std.testing.expectEqual(first_ts.nanoseconds, tw.first_byte_time.?.nanoseconds);

    try std.testing.expectEqualStrings("hello world", tw.written());
}
