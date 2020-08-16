const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("koino", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    addCommonRequirements(b, exe);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // I'm sure there's a way to deduplicate this with above.
    const test_exe = b.addTest("src/main.zig");
    addCommonRequirements(b, test_exe);

    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(&test_exe.step);
}

fn addCommonRequirements(b: *Builder, o: *std.build.LibExeObjStep) void {
    o.addPackagePath("ctregex", "vendor/ctregex/ctregex.zig");
}
