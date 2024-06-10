const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var deps = std.StringHashMap(*std.Build.Module).init(b.allocator);

    const pcre_pkg = b.dependency("libpcre.zig", .{ .optimize = optimize, .target = target });
    const htmlentities_pkg = b.dependency("htmlentities.zig", .{ .optimize = optimize, .target = target });
    const zunicode_pkg = b.dependency("zunicode", .{ .optimize = optimize, .target = target });
    const clap_pkg = b.dependency("clap", .{ .optimize = optimize, .target = target });

    try deps.put("clap", clap_pkg.module("clap"));
    try deps.put("libpcre", pcre_pkg.module("libpcre"));
    try deps.put("zunicode", zunicode_pkg.module("zunicode"));
    try deps.put("htmlentities", htmlentities_pkg.module("htmlentities"));

    const mod = b.addModule("koino", .{
        .root_source_file = b.path("src/koino.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addCommonRequirements(mod, &deps);

    const exe = b.addExecutable(.{
        .name = "koino",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    try addCommonRequirements(&exe.root_module, &deps);
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
    try addCommonRequirements(&test_exe.root_module, &deps);
    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(&test_exe.step);
}

fn addCommonRequirements(mod: *std.Build.Module, deps: *const std.StringHashMap(*std.Build.Module)) !void {
    var it = deps.iterator();
    while (it.next()) |entry| {
        mod.addImport(entry.key_ptr.*, entry.value_ptr.*);
    }
    mod.linkSystemLibrary("c", .{});
}
