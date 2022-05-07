const std = @import("std");

fn sdkRoot() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const sdk_root = sdkRoot();

const Sdk = @This();

pub fn getPackage(name: []const u8) std.build.Pkg {
    return std.build.Pkg{
        .name = name,
        .path = .{ .path = sdk_root ++ "/src/fatfs.zig" },
    };
}

pub fn link(exe: *std.build.LibExeObjStep, config: Config) void {
    exe.addCSourceFiles(&.{
        sdk_root ++ "/src/fatfs/ff.c",
        sdk_root ++ "/src/fatfs/ffunicode.c",
        sdk_root ++ "/src/fatfs/ffsystem.c",
    }, &.{"-std=c99"});
    exe.addIncludePath(sdk_root ++ "/src/fatfs");
    exe.linkLibC();

    inline for (comptime std.meta.fields(Config)) |fld| {
        addConfigField(exe, config, fld.name);
    }
}

fn addConfigField(exe: *std.build.LibExeObjStep, config: Config, comptime field_name: []const u8) void {
    const value = @field(config, field_name);
    const macro_name = @field(macro_names, field_name);

    const Type = @TypeOf(value);

    const type_info = @typeInfo(Type);

    const str_value: []const u8 = if (type_info == .Enum)
        exe.builder.fmt("{d}", .{@enumToInt(value)})
    else if (type_info == .Int)
        exe.builder.fmt("{d}", .{value})
    else if (Type == bool)
        exe.builder.fmt("{d}", .{@boolToInt(value)})
    else {
        @compileError("Unsupported config type: " ++ @typeName(Type));
    };

    exe.defineCMacro(macro_name, str_value);
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

const macro_names = struct {
    pub const read_only = "FF_FS_READONLY";
    pub const minimize = "FF_FS_MINIMIZE";
    pub const find = "FF_USE_FIND";
    pub const mkfs = "FF_USE_MKFS";
    pub const fastseek = "FF_USE_FASTSEEK";
    pub const expand = "FF_USE_EXPAND";
    pub const chmod = "FF_USE_CHMOD";
    pub const label = "FF_USE_LABEL";
    pub const forward = "FF_USE_FORWARD";
    pub const strfuncs = "FF_USE_STRFUNC";
    pub const printf_lli = "FF_PRINT_LLI";
    pub const printf_float = "FF_PRINT_FLOAT";
    pub const strf_encoding = "FF_STRF_ENCODE";
    pub const long_file_name = "FF_USE_LFN";
    pub const max_long_name_len = "FF_MAX_LFN";
};
