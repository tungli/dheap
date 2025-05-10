//! Heap with compile-time parameteric branching factor, also known as d-ary
//! heap. There is already a binary heap in the standard library:
//! [`std.PriorityQueue`](https://ziglang.org/documentation/master/std/#std.priority_queue)
//!
//! Performance notes:
//! - Heaps with higher branching factors are faster in inserting element and
//!   slower in removing elements. If you are going to insert and then remove all
//!   elements your best bet is probably the standard binary heap.
//! - The branching factor here is compile time to enable the optimization of
//!   division by the compiler, see e.g:
//!   https://en.wikipedia.org/wiki/Montgomery_modular_multiplication.
//! - If case you need to pop the top element and insert a new one, or vice
//!   versa, use the `replaceTop` member function to avoid paying the extra
//!   cost of "bubbling-up" the inserted element.
//!
//!
//! A simple benchmark for a rough idea: inserting 1e4 random `u64` elements into the heap:
//! ```
//! benchmark               time/run (avg ± σ)
//! ---------------------------------------------
//! [std]  only insert      229.52us ± 25.333us
//! [d=2]  only insert      222.877us ± 30.763us
//! [d=3]  only insert      194.461us ± 30.666us
//! [d=4]  only insert      166.156us ± 31.51us
//! [d=6]  only insert      146.055us ± 36.724us
//! [d=9]  only insert      132.419us ± 38.514us
//! [d=12] only insert      127.653us ± 39.015us
//! [d=18] only insert      121.178us ± 37.48us
//! [d=25] only insert      121.308us ± 38.305us
//! ---------------------------------------------
//! [std]  insert & pop     1.076ms ± 39.306us
//! [d=2]  insert & pop     897.273us ± 33.109us
//! [d=3]  insert & pop     918.428us ± 36.975us
//! [d=4]  insert & pop     983.259us ± 36.41us
//! [d=6]  insert & pop     1.112ms ± 36.679us
//! [d=9]  insert & pop     1.133ms ± 35.575us
//! [d=12] insert & pop     1.196ms ± 37.794us
//! [d=18] insert & pop     1.286ms ± 43.494us
//! [d=25] insert & pop     1.363ms ± 42.428us
//! ```

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

/// Some of the heap properties are meant to be accessed directly, without API calls.
/// * Access elements directly with `heap.items`.
/// * Obtain the number stored elements: `heap.items.len`.
/// * Obtain the capacity the heap can store new elements without reallocation: `heap.capacity`.
/// * Obtain the top element (unless empty): `heap.items[0]`.
///
/// Using a "less-than" for `compareFn` makes this a min-heap.
pub fn DHeap(
    comptime T: type,
    comptime Context: type,
    comptime compareFn: fn (context: Context, a: T, b: T) std.math.Order,
    comptime branching_factor: usize,
) type {
    return struct {
        items: []T,
        capacity: usize,
        allocator: Allocator,
        context: Context,

        pub fn init(allocator: Allocator, context: Context, init_capacity: usize) !@This() {
            var items = try allocator.alloc(T, init_capacity);
            items.len = 0;
            return .{
                .items = items,
                .capacity = init_capacity,
                .allocator = allocator,
                .context = context,
            };
        }

        pub fn deinit(self: @This()) void {
            self.allocator.free(self.items.ptr[0..self.capacity]);
        }

        /// Insert an element increasing capacity as needed.
        /// Complexity: `O(log(self.items.len))`.
        pub fn insert(self: *@This(), elem: T) !usize {
            if (self.capacity == self.items.len) {
                try self.increaseCapacity((self.capacity + 1) * 2);
            }

            self.items.len += 1;

            return self.insertUnchecked(elem);
        }

        /// Return the element on the top of the heap, removing it from the heap.
        /// The heap cannot be empty.
        /// Complexity: `O(log(self.items.len))`.
        pub fn pop(self: *@This()) T {
            assert(self.items.len != 0);

            const top = self.items[0];

            const last = self.items.len - 1;
            self.items[0] = self.items[last];
            self.items.len = last;
            _ = self.pushDown(0);

            return top;
        }

        /// Bubbles up `elem` into the heap.
        /// Does not modify the length of the heap nor checks its capacity!
        /// Complexity: `O(self.items.len)`.
        pub fn insertUnchecked(self: *@This(), elem: T) !usize {
            self.items[self.items.len - 1] = elem;
            return bubbleUp(self.*);
        }

        pub fn insertSlice(self: *@This(), slice: []T) !void {
            const needed = slice.len + self.items.len;
            if (self.capacity < needed) {
                try self.increaseCapacity((needed + 1) * 2);
            }

            for (slice) |elem| {
                self.insertUnchecked(elem);
            }
        }

        pub fn shrinkToFit(self: *@This()) !void {
            const new_len = self.items.len;

            self.items.len = self.capacity; // restore correct length in memory
            const new_items = try self.allocator.realloc(self.items, new_len);

            self.items.ptr = new_items.ptr;
            self.items.len = new_len;
            self.capacity = new_len;
        }

        /// The `slice` must have been allocated by the `allocator`.
        /// Complexity: `O(slice.len)`.
        pub fn fromOwnedSlice(allocator: Allocator, slice: []T, context: Context) @This() {
            const l = slice.len;

            var heap = @This(){
                .items = slice,
                .capacity = l,
                .allocator = allocator,
                .context = context,
            };

            var i = (l - 1) / branching_factor;
            while (i > 0) {
                _ = heap.pushDown(i);
                i -= 1;
            }
            _ = heap.pushDown(0);

            return heap;
        }

        /// Avoids "bubbling-up".
        /// Complexity: `O(log(self.items.len))`.
        pub fn replaceTop(self: *@This(), new_elem: T) T {
            assert(self.items.len != 0);

            const old_elem = self.items[0];
            self.items[0] = new_elem;
            _ = self.pushDown(0);

            return old_elem;
        }

        fn increaseCapacity(self: *@This(), new_capacity: usize) !void {
            const new_items = try self.allocator.realloc(self.items, new_capacity);
            self.items.ptr = new_items.ptr;
            self.capacity = new_items.len;
        }

        fn lowestDistChild(self: @This(), index: usize) usize {
            const child_0 = branching_factor * index + 1;
            var cur = child_0;
            inline for (1..branching_factor) |i| {
                const candidate = child_0 + i;

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
                const parent_i = (index - 1) / branching_factor;
                const parent = self.items[parent_i];

                if (compareFn(self.context, parent, cur) != .gt) break;

                self.items[index] = parent;
                index = parent_i;
            }
            self.items[index] = cur;
            return index;
        }

        fn pushDown(self: @This(), start: usize) usize {
            if (self.items.len == 0) return 0;

            var index = start;
            const cur = self.items[index];
            while (true) {
                const child_i = self.lowestDistChild(index);
                if (child_i >= self.items.len) {
                    break;
                }
                const child = self.items[child_i];
                if (compareFn(self.context, child, cur) == .lt) {
                    self.items[index] = child;
                    index = child_i;
                } else {
                    break;
                }
            }
            self.items[index] = cur;
            return index;
        }
    };
}

fn comp_fn_f64(context: void, a: f64, b: f64) std.math.Order {
    _ = context;
    return std.math.order(a, b);
}

fn comp_fn_u64(context: void, a: u64, b: u64) std.math.Order {
    _ = context;
    return std.math.order(b, a);
}

test "insert first, pop all, with shrinkToFit" {
    const gpa = std.testing.allocator;
    var heap = try DHeap(f64, void, comp_fn_f64, 4).init(gpa, {}, 0);
    defer heap.deinit();

    _ = try heap.insert(2.0);
    _ = try heap.insert(4.0);
    _ = try heap.insert(3.0);
    _ = try heap.insert(7.0);
    _ = try heap.insert(5.0);
    _ = try heap.insert(4.0);
    try heap.shrinkToFit();
    try heap.shrinkToFit();
    _ = try heap.insert(8.0);
    _ = try heap.insert(6.0);
    _ = try heap.insert(10.0);
    _ = try heap.insert(12.0);
    _ = try heap.insert(11.0);
    _ = try heap.insert(10.0);
    _ = try heap.insert(14.0);
    _ = try heap.insert(7.0);
    _ = try heap.insert(6.0);

    try std.testing.expectEqual(2.0, heap.pop());
    try std.testing.expectEqual(3.0, heap.pop());
    try std.testing.expectEqual(4.0, heap.pop());
    try std.testing.expectEqual(4.0, heap.pop());
    try std.testing.expectEqual(5.0, heap.pop());
    try std.testing.expectEqual(6.0, heap.pop());
    try std.testing.expectEqual(6.0, heap.pop());
    try std.testing.expectEqual(7.0, heap.pop());
    try heap.shrinkToFit();
    try std.testing.expectEqual(7.0, heap.pop());
    try std.testing.expectEqual(8.0, heap.pop());
    try std.testing.expectEqual(10.0, heap.pop());
    try std.testing.expectEqual(10.0, heap.pop());
    try std.testing.expectEqual(11.0, heap.pop());
    try heap.shrinkToFit();
    try std.testing.expectEqual(12.0, heap.pop());
    try std.testing.expectEqual(14.0, heap.pop());
    try std.testing.expectEqual(heap.items.len, 0);
}

test "rng insert or pop" {
    var rng = std.Random.DefaultPrng.init(1205910);
    const gpa = std.testing.allocator;

    var heap = try DHeap(u64, void, comp_fn_u64, 7).init(gpa, {}, 0);
    defer heap.deinit();

    var ref = std.PriorityQueue(u64, void, comp_fn_u64).init(gpa, {});
    defer ref.deinit();

    const n: usize = 1e5;

    for (0..(n / 10)) |_| {
        const val = rng.random().uintAtMost(u64, 3e3);
        _ = try heap.insert(val);
        try ref.add(val);
    }

    for (0..n) |_| {
        const do_pop: bool = rng.next() % 3 == 0;
        if (do_pop) {
            try std.testing.expectEqual(ref.remove(), heap.pop());
            if (heap.items.len == 0) break;
        } else {
            const val = rng.next();
            _ = try heap.insert(val);
            try ref.add(val);
        }
    }
}

fn less_than_u64(context: void, a: u64, b: u64) bool {
    return comp_fn_u64(context, a, b) == .lt;
}

test "fromOwnedSlice" {
    const gpa = std.testing.allocator;
    var rng = std.Random.DefaultPrng.init(859);

    const n: usize = 1e4;

    var slice = try gpa.alloc(u64, n);
    errdefer gpa.free(slice);
    const ref = try gpa.alloc(u64, n);
    defer gpa.free(ref);

    for (0..n) |i| {
        slice[i] = rng.random().uintAtMost(u64, 1e3);
    }

    @memcpy(ref, slice);
    std.sort.heap(u64, ref, {}, less_than_u64);

    var heap = DHeap(u64, void, comp_fn_u64, 5).fromOwnedSlice(gpa, slice, {});
    defer heap.deinit();

    for (0..n) |i| {
        try std.testing.expectEqual(ref[i], heap.pop());
    }
}

test "replaceTop" {
    const gpa = std.testing.allocator;
    var heap = try DHeap(f64, void, comp_fn_f64, 3).init(gpa, {}, 1);
    defer heap.deinit();

    _ = try heap.insert(2.0);
    _ = try heap.insert(4.0);
    _ = try heap.insert(3.0);
    _ = try heap.insert(7.0);
    _ = try heap.insert(3.0);
    _ = try heap.insert(4.0);
    _ = try heap.insert(8.0);

    try std.testing.expectEqual(2.0, heap.replaceTop(0.0));
    try std.testing.expectEqual(0.0, heap.pop());
    try std.testing.expectEqual(3.0, heap.pop());
    try std.testing.expectEqual(3.0, heap.replaceTop(12.0));
    try std.testing.expectEqual(4.0, heap.pop());
    try std.testing.expectEqual(4.0, heap.replaceTop(11.0));
    try std.testing.expectEqual(7.0, heap.pop());
    try std.testing.expectEqual(8.0, heap.pop());
    try std.testing.expectEqual(11.0, heap.pop());
    try std.testing.expectEqual(12.0, heap.pop());

    try std.testing.expectEqual(heap.items.len, 0);
}
