const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    var main_tests = b.addTest("test/tests.zig");
    main_tests.setBuildMode(mode);
    main_tests.addPackagePath("hsluv", "./hsluv.zig");

    const test_step = b.step("test", "Run hsluv tests");
    test_step.dependOn(&main_tests.step);
}
