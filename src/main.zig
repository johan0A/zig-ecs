const std = @import("std");
pub const ecs = @import("ecs.zig");

test {
    std.testing.refAllDecls(@This());
}

pub fn main() !void {}
