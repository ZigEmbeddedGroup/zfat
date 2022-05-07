const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zfat", "demo/main.zig");
    exe.addCSourceFiles(&.{
        "src/ff.c",
        "src/ffunicode.c",
        "src/ffsystem.c",
    }, &.{"-std=c99"});
    exe.addPackage(std.build.Pkg{ .name = "zfat", .path = .{ .path = "src/fatfs.zig" } });
    exe.addIncludePath("src");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

pub const Config = struct {
    read_only: bool = false,
    minimize: MinimizeLevel = .default,

    find: bool = true,
    mkfs: bool = true,

    fastseek: bool = true,
    expand: bool = true,
    chmod: bool = true,
    label: bool = true,
    forward: bool = true,
    strfuncs: StringFuncConfig = .disabled,
    printf_lli: bool = true,
    printf_float: bool = true,
    strf_encoding: StrfEncoding = .oem,
    long_file_name: bool = true,
    max_long_name_len: u8 = 255,
};

pub const StrfEncoding = enum(u2) {
    oem = 0,
    utf16_le = 1,
    utf16_be = 2,
    utf8 = 3,
};

pub const StringFuncConfig = enum(u2) {
    disabled = 0,
    enabled = 1,
    enabled_with_crlf = 2,
};

pub const MinimizeLevel = enum(u2) {
    default = 0,
    no_advanced = 1,
    no_dir_iteration = 2,
    no_lseek = 3,
};
