const std = @import("std");

pub fn FreeList(comptime T: type) type {
    return struct {
        const Self = @This();

        const ListType = std.ArrayList(?T);
        const AvailableQueueAsc = std.PriorityQueue(usize, void, struct {
            fn lessThan(_: void, a: T, b: T) std.math.Order {
                return std.math.order(a, b);
            }
        }.lessThan);

        list: ListType,
        available_queue: AvailableQueueAsc,

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .list = ListType.init(allocator),
                .available_queue = AvailableQueueAsc.init(allocator, {}),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit();
            self.available_queue.deinit();
        }

        pub fn get(self: Self, id: usize) ?T {
            if (self.list.items.len <= id) {
                return null;
            } else {
                return self.list.items[id];
            }
        }

        pub fn put(self: *Self, value: T) !usize {
            if (self.available_queue.removeOrNull()) |id| {
                if (id >= self.list.items.len) {
                    try self.list.append(value);
                    self.available_queue.deinit();
                    self.available_queue = AvailableQueueAsc.init(self.allocator, {});
                    return self.list.items.len - 1;
                }
                self.list.items[id] = value;
                return id;
            } else {
                try self.list.append(value);
                return self.list.items.len - 1;
            }
        }

        pub fn remove(self: *Self, id: usize) !void {
            self.list.items[id] = null;
            if (self.list.items.len == id + 1) {
                _ = self.list.pop();
                while (self.list.items.len > 0 and self.list.items[self.list.items.len - 1] == null) {
                    _ = self.list.pop();
                }
            } else {
                try self.available_queue.add(id);
            }
        }
    };
}

test "free list" {
    const allocator = std.testing.allocator;
    var list = FreeList(usize).init(allocator);
    defer list.deinit();

    var id_list = std.ArrayList(usize).init(allocator);
    defer id_list.deinit();
    for (0..10) |i| {
        try id_list.append(try list.put(i));
    }

    try list.remove(0);
    try list.remove(1);
    try list.remove(2);
    try list.remove(3);

    for (id_list.items) |id| {
        const value = list.get(id);
        try std.testing.expect(value == id or value == null);
    }

    try list.remove(4);
    try list.remove(5);

    try std.testing.expectEqual(@as(usize, 10), list.list.items.len);

    try list.remove(6);
    try list.remove(7);
    try list.remove(8);
    try list.remove(9);

    try std.testing.expectEqual(@as(usize, 0), list.list.items.len);
}
