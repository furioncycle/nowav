const std = @import("std");
const testing = std.testing;
const nowav = @import("nowav.zig");
const wavey = @import("wavey.zig");

const Hint = struct {
    extension: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,
};

test "find out file type by hints" {
    const hints: Hint = .{ .extension = "mp3" };
    _ = hints;
}
