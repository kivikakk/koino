const std = @import("std");
const linkPcre = @import("vendor/libpcre/build.zig").linkPcre;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var deps = std.StringHashMap(*std.build.Module).init(b.allocator);
    try deps.put("libpcre", b.addModule("libpcre", .{ .source_file = .{ .path = "vendor/libpcre/src/main.zig" } }));
    try deps.put("htmlentities", b.addModule("htmlentities", .{ .source_file = .{ .path = "vendor/htmlentities/src/main.zig" } }));
    try deps.put("clap", b.addModule("clap", .{ .source_file = .{ .path = "vendor/zig-clap/clap.zig" } }));
    try deps.put("zunicode", b.addModule("zunicode", .{ .source_file = .{ .path = "vendor/zunicode/src/zunicode.zig" } }));

    const exe = b.addExecutable(.{
        .name = "koino",
        .root_source_file = .{ .path = "src/main.zig" },
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
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    try addCommonRequirements(test_exe, &deps);
    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(&test_exe.step);
}

fn addCommonRequirements(cs: *std.build.CompileStep, deps: *const std.StringHashMap(*std.build.Module)) !void {
    var it = deps.iterator();
    while (it.next()) |entry| {
        cs.addModule(entry.key_ptr.*, entry.value_ptr.*);
    }
    try linkPcre(cs);
}
