A heap (priority queue) with compile-time parameteric branching factor, also
known as d-ary heap. 

Note that there is a binary heap in the standard library if you do not want
to use this module:
[`std.PriorityQueue`](https://ziglang.org/documentation/master/std/#std.priority_queue)

Performance notes:
- Heaps with higher branching factors are faster in inserting element and
  slower in removing elements.
- The branching factor here is compile time to enable the optimization of
  division by the compiler, see e.g:
  [Montgomery modular multiplication](https://en.wikipedia.org/wiki/Montgomery_modular_multiplication).
- If case you need to pop the top element and insert a new one, or vice
  versa, use the `replaceTop` member function to avoid paying the extra
  cost of "bubbling-up" the inserted element.
