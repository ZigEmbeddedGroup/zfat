const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zfat_dep = b.dependency("zfat", .{
        .code_page = .us,
        .@"sector-size" = @as(u32, 512),
        .@"volume-count" = @as(u32, 5),
        // .@"volume-names" = @as([]const u8, "a,b,c,h,z"), // TODO(fqu): Requires VolToPart to be defined

        // Enable features:
        .find = true,
        .mkfs = true,
        .fastseek = true,
        .expand = true,
        .chmod = true,
        .label = true,
        .forward = true,
        .relative_path_api = .enabled_with_getcwd,
        // .multi_partition = true, // TODO(fqu): Requires VolToPart to be defined
        .lba64 = true,
        .use_trim = true,
        .exfat = true,
    });
    const zfat_mod = zfat_dep.module("zfat");

    const op_tester = b.addExecutable(.{
        .name = "zfat-op-tester",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("op_tester.zig"),
    });
    op_tester.root_module.addImport("zfat", zfat_mod);
    op_tester.linkLibC();

    b.installArtifact(op_tester);
}
