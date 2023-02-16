const std = @import("std");
const FatSdk = @import("Sdk.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zfat",
        .root_source_file = .{ .path = "demo/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const config = FatSdk.Config{};
    exe.addModule("zfat", FatSdk.createModule(b, config));
    FatSdk.link(exe, config);

    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
