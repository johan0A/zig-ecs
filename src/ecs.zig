const std = @import("std");
const component_types_file = @import("component_types.zig");

pub fn FreeList(comptime T: type) type {
    return struct {
        const Self = @This();

        const InputType = T;

        const ListType = std.ArrayList(?T);
        const AvailableQueueAsc = std.PriorityQueue(usize, void, struct {
            fn lessThan(_: void, a: usize, b: usize) std.math.Order {
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

        pub fn get(self: Self, id: usize) ?*T {
            if (self.list.items.len <= id) {
                return null;
            } else {
                if (self.list.items[id] == null) {
                    return null;
                } else {
                    return &self.list.items[id].?;
                }
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
        try std.testing.expect(value == null or value.?.* == id);
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

const ComponentsManager = struct {
    const Self = @This();

    const component_types = blk: {
        const components_decls = @typeInfo(component_types_file).Struct.decls;
        var components_types_temp: [components_decls.len]type = undefined;
        break :blk for (components_decls, 0..) |decl, i| {
            const decl_type = @field(component_types_file, decl.name);
            if (@typeInfo(decl_type) != .Struct) @compileError("all component types must be a struct");
            components_types_temp[i] = decl_type;
        } else components_types_temp;
    };

    const components_lists_types = blk: {
        var tuple_fields: [component_types.len]type = undefined;
        break :blk for (component_types, 0..) |component_type, i| {
            tuple_fields[i] = FreeList(component_type);
        } else tuple_fields;
    };

    pub const component_types_count = component_types.len;

    allocator: std.mem.Allocator,
    components_lists: std.meta.Tuple(&components_lists_types),

    pub fn init(allocator: std.mem.Allocator) Self {
        var result = Self{
            .allocator = allocator,
            .components_lists = undefined,
        };
        inline for (components_lists_types, 0..) |component_list_type, i| {
            result.components_lists[i] = component_list_type.init(allocator);
        }
        return result;
    }

    pub fn deinit(self: *Self) void {
        inline for (&self.components_lists) |*component_list| {
            component_list.deinit();
        }
    }

    pub fn type_to_id(comptime component_type: type) usize {
        inline for (component_types, 0..) |component_type_, i| {
            if (component_type == component_type_) return i;
        }
        @compileError("Component type not found");
    }

    pub fn put_by_type_id(self: *Self, comptime component_type_id: usize, value: component_types[component_type_id]) !usize {
        return self.components_lists[component_type_id].put(value);
    }

    pub fn put(self: *Self, comptime component_type: type, value: component_type) !usize {
        return self.put_by_type_id(ComponentsManager.type_to_id(component_type), value);
    }

    pub fn remove_by_type_id(self: *Self, comptime component_type_id: usize, component_id: usize) !void {
        return self.components_lists[component_type_id].remove(component_id);
    }

    pub fn remove(self: *Self, comptime component_type: type, component_id: usize) !void {
        return self.remove_by_type_id(ComponentsManager.type_to_id(component_type), component_id);
    }

    pub fn get_by_type_id(self: Self, comptime component_type_id: usize, component_id: usize) ?*component_types[component_type_id] {
        return self.components_lists[component_type_id].get(component_id);
    }

    pub fn get(self: Self, comptime component_type: type, component_id: usize) ?*component_type {
        return self.get_by_type_id(ComponentsManager.type_to_id(component_type), component_id);
    }
};

test "components manager" {
    const allocator = std.testing.allocator;
    var components_manager = ComponentsManager.init(allocator);
    defer components_manager.deinit();

    const test_pos_component = component_types_file.Test2DPosComponent{ .x = 1, .y = 2 };
    const test_id = try components_manager.put(@TypeOf(test_pos_component), test_pos_component);
    try std.testing.expectEqual(
        test_pos_component,
        components_manager.get(
            @TypeOf(test_pos_component),
            test_id,
        ).?.*,
    );
    try components_manager.remove(@TypeOf(test_pos_component), test_id);
}
