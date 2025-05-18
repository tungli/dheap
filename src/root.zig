//! A heap (priority queue) with compile-time parameteric branching factor, also
//! known as d-ary heap.
//!
//! Note that there is a binary heap in the standard library if you do not want
//! to use this module:
//! [`std.PriorityQueue`](https://ziglang.org/documentation/master/std/#std.priority_queue)
//!
//! Performance notes:
//! - Heaps with higher branching factors are faster in inserting element and
//!   slower in removing elements.
//! - The branching factor here is compile time to enable the optimization of
//!   division by the compiler, see e.g:
//!   [Montgomery modular multiplication](https://en.wikipedia.org/wiki/Montgomery_modular_multiplication).
//! - If case you need to pop the top element and insert a new one, or vice
//!   versa, use the `replaceTop` member function to avoid paying the extra
//!   cost of "bubbling-up" the inserted element.

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

        pub fn isValid(self: @This()) bool {
            for (0..self.items.len) |i| {
                for (0..branching_factor) |nth_child| {
                    const child_i = branching_factor * i + 1 + nth_child;
                    if (child_i < self.items.len) {
                        if (compareFn(self.context, self.items[i], self.items[child_i]) == .gt) {
                            return false;
                        }
                    }
                    else return true;
                }
            }
            return true;
        }

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
        pub fn insert(self: *@This(), elem: T) !void {
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
            self.items[0] = self.removeLast();
            self.pushDown(0);

            return top;
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
                heap.pushDown(i);
                i -= 1;
            }
            heap.pushDown(0);

            return heap;
        }

        /// Avoids "bubbling-up".
        /// Complexity: `O(log(self.items.len))`.
        pub fn replaceTop(self: *@This(), new_elem: T) T {
            assert(self.items.len != 0);

            const old_elem = self.items[0];
            self.items[0] = new_elem;
            self.pushDown(0);

            return old_elem;
        }

        pub fn increaseCapacity(self: *@This(), new_capacity: usize) !void {
            const new_items = try self.allocator.realloc(self.items, new_capacity);
            self.items.ptr = new_items.ptr;
            self.capacity = new_items.len;
        }

        /// Complexity: `O(log(self.items.len))`
        pub fn update(self: *@This(), index: usize, new_val: T) void {
            const old_val = self.items[index];
            self.items[index] = new_val;

            switch (compareFn(self.context, new_val, old_val)) {
                .lt => self.bubbleUp(index),
                .gt => self.pushDown(index),
                .eq => {},
            }
        }

        /// Remove and return `self.items[self.items.len - 1]`
        /// Complexity: constant
        pub fn removeLast(self: *@This()) T {
            const last_i = self.items.len - 1;
            const elem = self.items[last_i];
            self.items.len = last_i;
            return elem;
        }

        /// Return an element at located at `self.items[index]` removing it from the heap.
        /// Complexity: `O(log(self.items.len))`.
        pub fn remove(self: *@This(), index: usize) T {
            if (index == 0) return self.pop();

            assert(self.items.len > index);

            // the last element special case (note: self.items.len is different after `plugHole`)
            if (index == self.items.len - 1) {
                return self.removeLast();
            }

            const elem = self.items[index];
            self.items[index] = self.removeLast();

            // the new element might violate heap invariant in both ways
            const parent_i = (index - 1) / branching_factor;
            if (compareFn(self.context, self.items[parent_i], self.items[index]) == .gt) {
                self.bubbleUp(index);
            } else {
                // if elem has no children, return elem without pushDown
                if (branching_factor * index < self.items.len) {
                    self.pushDown(index);
                }
            }

            return elem;
        }

        fn pushDown(self: @This(), start: usize) void {
            if (self.items.len == 0) return;

            var index = start;
            const cur = self.items[index];
            while (true) {
                // find lowest child
                const child_0 = branching_factor * index + 1;
                if (child_0 >= self.items.len) {
                    break;
                }
                var lowest_child_i: usize = child_0;
                for (1..branching_factor) |i| {
                    const candidate = child_0 + i;

                    if (candidate < self.items.len) {
                        const order = compareFn(self.context, self.items[lowest_child_i], self.items[candidate]);
                        if (order == .gt) {
                            lowest_child_i = candidate;
                        }
                    }
                }

                // swap if lower
                const child = self.items[lowest_child_i];
                if (compareFn(self.context, child, cur) == .lt) {
                    self.items[index] = child;
                    index = lowest_child_i;
                } else {
                    break;
                }
            }
            self.items[index] = cur;
        }

        fn bubbleUp(self: @This(), start: usize) void {
            var index = start;
            const cur = self.items[index];
            while (index > 0) {
                const parent_i = (index - 1) / branching_factor;
                const parent = self.items[parent_i];

                if (compareFn(self.context, cur, parent) == .gt) break;

                self.items[index] = parent;
                index = parent_i;
            }
            self.items[index] = cur;
        }

        fn insertUnchecked(self: *@This(), elem: T) !void {
            const l = self.items.len - 1;
            self.items[l] = elem;
            bubbleUp(self.*, l);
        }
    };
}

// ------ TESTS ------- //

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
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(4.0);
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(3.0);
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(7.0);
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(5.0);
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(4.0);
    try heap.shrinkToFit();
    try heap.shrinkToFit();
    _ = try heap.insert(8.0);
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(6.0);
    _ = try heap.insert(10.0);
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(12.0);
    _ = try heap.insert(11.0);
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(10.0);
    _ = try heap.insert(14.0);
    try std.testing.expect(heap.isValid());
    _ = try heap.insert(7.0);
    _ = try heap.insert(6.0);
    try std.testing.expect(heap.isValid());

    try std.testing.expectEqual(2.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(3.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(4.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(4.0, heap.pop());
    try std.testing.expectEqual(5.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(6.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(6.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(7.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try heap.shrinkToFit();
    try std.testing.expectEqual(7.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(8.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(10.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(10.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(11.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try heap.shrinkToFit();
    try std.testing.expectEqual(12.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(14.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(heap.items.len, 0);
}

test "rng insert|pop|update|remove" {
    const seed = 205910;
    var rng = std.Random.DefaultPrng.init(seed);
    const gpa = std.testing.allocator;
    const at_most: u64 = 3e3;

    var heap = try DHeap(u64, void, comp_fn_u64, 4).init(gpa, {}, 0);
    defer heap.deinit();

    var ref = std.PriorityQueue(u64, void, comp_fn_u64).init(gpa, {});
    defer ref.deinit();

    const n: usize = 1e4;

    for (0..(n / 10)) |_| {
        const val = rng.random().uintAtMost(u64, at_most);
        try heap.insert(val);
        try ref.add(val);
    }

    for (0..n) |_| {
        const do_pop: bool = rng.next() % 3 == 0;
        const do_update: bool = rng.next() % 5 == 0;
        const do_remove: bool = rng.next() % 6 == 0;
        if (do_pop) {
            try std.testing.expectEqual(ref.remove(), heap.pop());
            if (heap.items.len == 0) break;
        } else if (do_update) {
            const val = rng.random().uintAtMost(u64, at_most);
            var index = rng.random().uintAtMost(usize, heap.items.len - 1);
            // find first occurence
            for (0..heap.items.len) |i| {
                if (heap.items[index] == heap.items[i]) {
                    index = i;
                    break;
                }
            }
            try ref.update(heap.items[index], val);
            heap.update(index, val);
        } else if (do_remove) {
            const index = rng.random().uintAtMost(usize, heap.items.len - 1);
            var ref_index: usize = undefined;
            for (0..ref.items.len) |i| {
                if (ref.items[i] == heap.items[index]) {
                    ref_index = i;
                    break;
                }
            }
            try std.testing.expectEqual(ref.removeIndex(ref_index), heap.remove(index));
            if (heap.items.len == 0) break;
        } else {
            const val = rng.random().uintAtMost(u64, at_most);
            try heap.insert(val);
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

    try heap.insert(2.0);
    try heap.insert(4.0);
    try heap.insert(3.0);
    try heap.insert(7.0);
    try heap.insert(3.0);
    try heap.insert(4.0);
    try heap.insert(8.0);
    try std.testing.expect(heap.isValid());

    try std.testing.expectEqual(2.0, heap.replaceTop(0.0));
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(0.0, heap.pop());
    try std.testing.expectEqual(3.0, heap.pop());
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(3.0, heap.replaceTop(12.0));
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(4.0, heap.pop());
    try std.testing.expectEqual(4.0, heap.replaceTop(11.0));
    try std.testing.expect(heap.isValid());
    try std.testing.expectEqual(7.0, heap.pop());
    try std.testing.expectEqual(8.0, heap.pop());
    try std.testing.expectEqual(11.0, heap.pop());
    try std.testing.expectEqual(12.0, heap.pop());

    try std.testing.expectEqual(heap.items.len, 0);
}
