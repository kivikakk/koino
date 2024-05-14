const std = @import("std");
const linkPcre = @import("vendor/libpcre.zig/build.zig").linkPcre;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var deps = std.StringHashMap(*std.Build.Module).init(b.allocator);
    const libpcre = b.addModule("libpcre", .{
        .root_source_file = b.path("vendor/libpcre.zig/src/main.zig"),
        .target = target,
    });
    try linkPcre(b, libpcre);
    try deps.put("libpcre", libpcre);
    try deps.put("htmlentities", b.addModule("htmlentities", .{ .root_source_file = b.path("vendor/htmlentities.zig/src/main.zig") }));
    try deps.put("clap", b.addModule("clap", .{ .root_source_file = b.path("vendor/zig-clap/clap.zig") }));
    try deps.put("zunicode", b.addModule("zunicode", .{ .root_source_file = b.path("vendor/zunicode/src/zunicode.zig") }));

    const exe = b.addExecutable(.{
        .name = "koino",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addCommonRequirements(exe, &deps);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_exe = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addCommonRequirements(test_exe, &deps);
    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(&test_exe.step);
}

fn addCommonRequirements(cs: *std.Build.Step.Compile, deps: *const std.StringHashMap(*std.Build.Module)) !void {
    var it = deps.iterator();
    while (it.next()) |entry| {
        cs.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
    }
    cs.linkLibC();
}
