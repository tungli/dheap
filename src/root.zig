const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const init_capacity: usize = 13;

pub fn DHeap(
    comptime T: type,
    comptime Context: type,
    comptime compareFn: fn (context: Context, a: T, b: T) std.math.Order,
) type {
    return struct {
        items: []T,
        capacity: usize,
        allocator: Allocator,
        context: Context,
        branching_factor: usize,

        pub fn init(allocator: Allocator, context: Context, branching_factor: usize) !@This() {
            var items = try allocator.alloc(T, init_capacity);
            items.len = 0;
            return .{
                .items = items,
                .capacity = init_capacity, 
                .allocator = allocator,
                .context = context,
                .branching_factor = branching_factor,
            };
        }

        pub fn deinit(self: @This()) void {
            self.allocator.free(self.items.ptr[0..self.capacity]);
        }

        pub fn insert(self: *@This(), elem: T) !usize {
            if (self.capacity == self.items.len) {
                try increaseCapacity(self);
            }

            const l = self.items.len + 1;
            self.items.len = l;
            self.items[l - 1] = elem;

            return bubbleUp(self.*);
        }

        pub fn pop(self: *@This()) T {
            assert(self.items.len != 0);

            const top = self.items[0];

            const last = self.items.len - 1;
            self.items[0] = self.items[last];
            self.items.len = last;
            _ = self.pushDown();

            return top;
        }
        
        pub fn prettyPrint(self: @This()) void {
            var n: usize = 1;
            var i: usize = 0;
            var level: usize = 0;
            while (i < self.items.len) {
                std.debug.print("|  ", .{});
                while (i < n) {
                    std.debug.print("{}  |  ", .{self.items[i]});

                    i += 1;
                    
                    if (i == self.items.len) {
                        std.debug.print("\n", .{});
                        return;
                    }
                }
                level += 1;
                n += std.math.powi(usize, self.branching_factor, level) catch unreachable;
                std.debug.print("\n", .{});
            }

        }

        fn increaseCapacity(self: *@This()) !void {
            const new_capacity = (self.capacity + 1) * 2;
            const new_items = try self.allocator.realloc(self.items, new_capacity);
            self.items.ptr = new_items.ptr;
            self.capacity = new_items.len;
        }

        fn parentIndex(index: usize, d: usize) usize {
            return (index - 1) / d;
        }

        fn nChild(index: usize, n: usize, d: usize) usize {
            return d * index + n + 1;
        }

        fn closestChildIndex(self: @This(), index: usize) usize {
            var cur = nChild(index, 0, self.branching_factor);
            for (1..self.branching_factor) |i| {
                const candidate = nChild(index, i, self.branching_factor);

                if (candidate >= self.items.len) {
                    break;
                }

                const order = compareFn(self.context, self.items[cur], self.items[candidate]);
                if (order == .gt) {
                    cur = candidate;
                }

            }
            return cur;
        }

        fn bubbleUp(self: @This()) usize {
            var index = self.items.len - 1;
            const cur = self.items[index];
            while (index > 0) {
                const parent_i = parentIndex(index, self.branching_factor);
                const parent = self.items[parent_i];
                if (compareFn(self.context, parent, cur) == .gt) {
                    self.items[index] = parent;
                    index = parent_i;
                }
                else {
                    break;
                }
            }
            self.items[index] = cur;
            return index;
        }

        fn firstLeaf(self: @This()) i64 {
            const i: i64 = @intCast(self.items.len);
            const d: i64 = @intCast(self.branching_factor);
            return @divFloor(i - 2, d) + 1;

        }

        fn pushDown(self: @This()) usize {
            if (self.items.len == 0) return 0;
            var index: usize = 0;
            const cur = self.items[index];
            while (index < self.firstLeaf()) {
                const child_i = self.closestChildIndex(index);
                const child = self.items[child_i];
                if (compareFn(self.context, child, cur) == .lt) {
                    self.items[index] = child;
                    index = child_i;
                }
                else {
                    break;
                }
            }
            self.items[index] = cur;
            return index;
        }
    };
}


fn comp_fn(context: void, a: f64, b: f64) std.math.Order {
    _ = context;
    return std.math.order(a, b);
}


test "test0" {
    const gpa = std.testing.allocator;
    var heap = try DHeap(f64, void, comp_fn).init(gpa, {}, 4);
    defer heap.deinit();

    _ = try heap.insert(2.0);
    _ = try heap.insert(4.0);
    _ = try heap.insert(3.0);
    _ = try heap.insert(7.0);
    _ = try heap.insert(5.0);
    _ = try heap.insert(4.0);
    _ = try heap.insert(8.0);
    _ = try heap.insert(6.0);
    _ = try heap.insert(10.0);
    _ = try heap.insert(12.0);
    _ = try heap.insert(11.0);
    _ = try heap.insert(10.0);
    _ = try heap.insert(14.0);
    _ = try heap.insert(7.0);
    _ = try heap.insert(6.0);

    // heap.prettyPrint();

    try std.testing.expectEqual(2.0, heap.pop());
    try std.testing.expectEqual(3.0, heap.pop());
    try std.testing.expectEqual(4.0, heap.pop());
    try std.testing.expectEqual(4.0, heap.pop());
    try std.testing.expectEqual(5.0, heap.pop());
    try std.testing.expectEqual(6.0, heap.pop());
    try std.testing.expectEqual(6.0, heap.pop());
    try std.testing.expectEqual(7.0, heap.pop());
    try std.testing.expectEqual(7.0, heap.pop());
    try std.testing.expectEqual(8.0, heap.pop());
    try std.testing.expectEqual(10.0, heap.pop());
    try std.testing.expectEqual(10.0, heap.pop());
    try std.testing.expectEqual(11.0, heap.pop());
    try std.testing.expectEqual(12.0, heap.pop());
    try std.testing.expectEqual(14.0, heap.pop());
    try std.testing.expectEqual(heap.items.len, 0);
}
