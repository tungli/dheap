const std = @import("std");

pub fn build(b: *std.Build) void {
    const source_file = b.path("src/root.zig");

    _ = b.addModule("dheap", .{
        .root_source_file = source_file
    });

    const tests = b.addTest(.{
        .root_source_file = source_file,
    });

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
