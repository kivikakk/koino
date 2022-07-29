const std = @import("std");
const linkPcre = @import("vendor/libpcre/build.zig").linkPcre;

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("koino", "src/main.zig");
    try addCommonRequirements(exe, target, mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_exe = b.addTest("src/main.zig");
    try addCommonRequirements(test_exe, target, mode);
    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(&test_exe.step);
}

fn addCommonRequirements(exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget, mode: std.builtin.Mode) !void {
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("libpcre", "vendor/libpcre/src/main.zig");
    exe.addPackagePath("htmlentities", "vendor/htmlentities/src/main.zig");
    exe.addPackagePath("clap", "vendor/zig-clap/clap.zig");
    exe.addPackagePath("zunicode", "vendor/zunicode/src/zunicode.zig");
    try linkPcre(exe);
}
