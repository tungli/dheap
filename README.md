Heap with compile-time parameteric branching factor, also known as d-ary
heap. 

Note that there is a binary heap in the standard library if you do not want
to use this module:
[`std.PriorityQueue`](https://ziglang.org/documentation/master/std/#std.priority_queue)

Performance notes:
- Heaps with higher branching factors are faster in inserting element and
  slower in removing elements. If you are going to insert and then remove all
  elements a binary heap is already quite fast and a branching factor
  higher than 5 is probably going to be less optimal. The optimal branching
  factor is usually around 4.
- The branching factor here is compile time to enable the optimization of
  division by the compiler, see e.g:
  [Montgomery modular multiplication](https://en.wikipedia.org/wiki/Montgomery_modular_multiplication).
- If case you need to pop the top element and insert a new one, or vice
  versa, use the `replaceTop` member function to avoid paying the extra
  cost of "bubbling-up" the inserted element.

A simple benchmark for a rough idea: inserting 1e4 random `u64` elements into the heap:
```
benchmark                    time/run (avg ± σ)
-------------------------------------------------
[std]  only insert           243.539us ± 29.004us
[d=2]  only insert           227.793us ± 32.214us
[d=3]  only insert           193.544us ± 31.476us
[d=4]  only insert           164.575us ± 33.934us
[d=6]  only insert           147.85us ± 32.493us
[d=9]  only insert           129.839us ± 23.473us
[d=12] only insert           128.567us ± 38.791us
[d=18] only insert           122.77us ± 42.012us
[d=25] only insert           120.442us ± 29.357us
[std]  insert & pop          1.077ms ± 33.59us
[d=2]  insert & pop          553.248us ± 27.777us
[d=3]  insert & pop          566.435us ± 28.033us
[d=4]  insert & pop          545.761us ± 22.576us
[d=6]  insert & pop          644.93us ± 37.126us
[d=9]  insert & pop          729.345us ± 49.433us
[d=12] insert & pop          941.802us ± 33.717us
[d=18] insert & pop          1.088ms ± 48.944us
[d=25] insert & pop          1.422ms ± 149.116us
```
where `d` is the branching factor and `std` stands for the `std.PriorityQueue` (binary heap).
