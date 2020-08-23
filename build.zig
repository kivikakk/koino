const std = @import("std");
const linkPcre = @import("vendor/libpcre.zig/build.zig").linkPcre;

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("koino", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    try addCommonRequirements(exe);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_exe = b.addTest("src/main.zig");
    try addCommonRequirements(test_exe);
    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(&test_exe.step);
}

fn addCommonRequirements(exe: *std.build.LibExeObjStep) !void {
    exe.addPackagePath("libpcre", "vendor/libpcre.zig/src/main.zig");
    exe.addPackagePath("htmlentities", "vendor/htmlentities.zig/src/main.zig");
    exe.addPackagePath("clap", "vendor/zig-clap/clap.zig");
    exe.addPackagePath("zunicode", "vendor/zunicode/src/zunicode.zig");
    try linkPcre(exe);
}
